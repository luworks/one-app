"""Actual SDK orchestration over one injected Responses budget gateway.

The transport is deliberately in-process: even SDK retries cannot bypass the
harness. The SDK client only sees a non-secret sentinel and an invalid base URL.
"""
from __future__ import annotations

import asyncio
import copy
import json
import os
from pathlib import Path
from typing import Any, Callable, Protocol, TypedDict

os.environ["LANGCHAIN_TRACING_V2"] = "false"
os.environ["LANGSMITH_TRACING"] = "false"

MODEL = "gpt-6-luna"
INSTRUCTIONS = (
    "You are a synthetic Today planner. Use only supplied planner tools. "
    "Preserve task identity, constraints and revisions. Changes are proposals; "
    "only explicit harness controls may apply them. Tool errors are feedback. "
    "Do not claim a write succeeded without its receipt."
)


class GatewayLike(Protocol):
    def handle(self, payload: dict, *, synthetic: bool = True) -> dict: ...


class FrameworkAdapter:
    def __init__(self, gateway: GatewayLike, tools: list[dict],
                 dispatch: Callable[[str, dict], Any], storage: Path):
        self.gateway = gateway
        self.tools = copy.deepcopy(tools)
        self.dispatch = dispatch
        self.storage = Path(storage)
        self.storage.mkdir(parents=True, exist_ok=True)
        self.requests: list[dict] = []
        self.gateway_request_ids: list[str] = []
        self.events: list[dict] = []

    def call_gateway(self, payload: dict) -> dict:
        if payload.get("model") != MODEL:
            raise ValueError("Only gpt-6-luna is authorized")
        if payload.get("stream"):
            raise ValueError("Streaming is not supported by this adapter")
        payload = copy.deepcopy(payload)
        payload.update(store=False, service_tier="default", reasoning={"effort": "medium"})
        payload.setdefault("max_output_tokens", 2048)
        if not 1 <= payload["max_output_tokens"] <= 4096:
            raise ValueError("Output token limit exceeded")
        if any(tool.get("type") != "function" for tool in payload.get("tools", [])):
            raise ValueError("Only common planner function tools are permitted")
        canonical = {tool["name"]: tool for tool in self.tools}
        names = [tool["name"] for tool in payload.get("tools", [])]
        if len(names) != len(set(names)) or any(name not in canonical for name in names):
            raise ValueError("SDK requested an unapproved planner tool")
        # SDKs normalize strict flags differently. Freeze the same authority-owned
        # wire schemas for every candidate; retain native execution/history loops.
        changes = [{"name": tool["name"], "sdk_strict": tool.get("strict"),
                    "canonical_strict": canonical[tool["name"]].get("strict")}
                   for tool in payload.get("tools", []) if tool != canonical[tool["name"]]]
        if changes:
            self.events.append({"type": "sdk_schema_normalized", "tools": changes})
        payload["tools"] = [copy.deepcopy(canonical[name]) for name in names]
        self.requests.append(copy.deepcopy(payload))
        result = self.gateway.handle(payload, synthetic=True)
        request_id = result.get("_gateway", {}).get("request_id")
        if request_id:
            self.gateway_request_ids.append(request_id)
        self.events.append({"type": "model_response", "gateway_request_id": request_id})
        return result

    async def execute_tool(self, name: str, arguments: dict) -> Any:
        self.events.append({"type": "tool_started", "name": name, "arguments": arguments})
        from jsonschema.exceptions import ValidationError
        try:
            result = self.dispatch(name, arguments)
            if hasattr(result, "__await__"):
                result = await result
        except (ValueError, KeyError, ValidationError) as error:
            result = {"error": type(error).__name__, "message": str(error)}
        self.events.append({"type": "tool_completed", "name": name, "output": result})
        return result

    def client(self):
        import httpx2
        from openai import AsyncOpenAI

        async def transport(request):
            if request.url.path != "/v1/responses" or request.method != "POST":
                raise ValueError("Unexpected SDK endpoint")
            result = await asyncio.to_thread(self.call_gateway, json.loads(request.content))
            request_id = result.get("_gateway", {}).get("request_id", "offline")
            return httpx2.Response(200, json=result, headers={"x-request-id": request_id})

        return AsyncOpenAI(
            api_key="lab-local-sentinel-not-a-provider-key", base_url="https://gateway.invalid/v1",
            max_retries=0, http_client=httpx2.AsyncClient(transport=httpx2.MockTransport(transport)),
        )


class PydanticAdapter(FrameworkAdapter):
    """PydanticAI owns tool execution, validation and message history encoding."""

    async def run(self, session_id: str, text: str) -> str:
        from pydantic_ai import Agent, Tool
        from pydantic_ai.messages import ModelMessagesTypeAdapter
        from pydantic_ai.models.openai import OpenAIResponsesModel
        from pydantic_ai.providers.openai import OpenAIProvider
        from pydantic_ai.usage import UsageLimits
        tools = []
        def bind_tool(name):
            async def invoke(**kwargs):
                return await self.execute_tool(name, kwargs)
            return invoke
        for schema in self.tools:
            tools.append(Tool.from_schema(bind_tool(schema["name"]), name=schema["name"],
                                         description=schema.get("description", ""),
                                         json_schema=schema["parameters"]))
        history_path = self.storage / "pydantic-history.json"
        histories = json.loads(history_path.read_text()) if history_path.exists() else {}
        history = ModelMessagesTypeAdapter.validate_python(histories.get(session_id, []))
        async with self.client() as client:
            model = OpenAIResponsesModel(MODEL, provider=OpenAIProvider(openai_client=client))
            agent = Agent(model, tools=tools, instructions=INSTRUCTIONS, retries=0,
                          model_settings={"max_tokens": 2048, "max_retries": 0,
                                          "parallel_tool_calls": False, "openai_store": False,
                                          "openai_reasoning_effort": "medium",
                                          "openai_prompt_cache_diagnostics": False})
            result = await agent.run(text, message_history=history,
                                     usage_limits=UsageLimits(request_limit=8, tool_calls_limit=16))
        histories[session_id] = json.loads(result.all_messages_json())
        temporary = history_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(histories))
        temporary.replace(history_path)
        return str(result.output)


class AgentsAdapter(FrameworkAdapter):
    """Agents SDK Runner owns the loop; SQLiteSession owns restartable history."""

    async def run(self, session_id: str, text: str) -> str:
        from agents import (Agent, FunctionTool, ModelSettings, OpenAIResponsesModel,
                            RunConfig, Runner, SQLiteSession, set_tracing_disabled)
        from openai.types.shared import Reasoning
        from agents.retry import ModelRetrySettings
        set_tracing_disabled(True)
        tools = []
        for schema in self.tools:
            async def invoke(context, arguments, _name=schema["name"]):
                return json.dumps(await self.execute_tool(_name, json.loads(arguments)))
            tools.append(FunctionTool(schema["name"], schema.get("description", ""),
                                      schema["parameters"], invoke, strict_json_schema=False))
        session = SQLiteSession(session_id, self.storage / "agents-session.sqlite")
        try:
            async with self.client() as client:
                agent = Agent(name="Today research", instructions=INSTRUCTIONS, tools=tools,
                              model=OpenAIResponsesModel(MODEL, client),
                              model_settings=ModelSettings(max_tokens=2048, store=False,
                                                           parallel_tool_calls=False,
                                                           reasoning=Reasoning(effort="medium"),
                                                           retry=ModelRetrySettings(max_retries=0)))
                result = await Runner.run(agent, text, session=session, max_turns=8,
                                          run_config=RunConfig(tracing_disabled=True))
                return str(result.final_output)
        finally:
            session.close()


class GraphState(TypedDict):
    messages: list[dict]
    calls: list[dict]
    reply: str
    steps: int


class LangGraphAdapter(FrameworkAdapter):
    """Explicit graph control flow and native SQLite checkpoints around Responses."""

    async def run(self, session_id: str, text: str) -> str:
        from langgraph.graph import StateGraph, START, END
        from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver

        async def model(state: GraphState):
            if state["steps"] >= 8:
                raise RuntimeError("Model request limit exceeded")
            payload = {"model": MODEL, "instructions": INSTRUCTIONS,
                       "input": state["messages"], "tools": self.tools, "max_output_tokens": 2048}
            response = await asyncio.to_thread(self.call_gateway, payload)
            output = response["output"]
            calls = [item for item in output if item["type"] == "function_call"]
            reply = "".join(part.get("text", "") for item in output
                            if item["type"] == "message" for part in item.get("content", []))
            return {"messages": state["messages"] + output, "calls": calls,
                    "reply": reply, "steps": state["steps"] + 1}

        async def tools(state: GraphState):
            outputs = []
            for call in state["calls"]:
                result = await self.execute_tool(call["name"], json.loads(call["arguments"]))
                outputs.append({"type": "function_call_output", "call_id": call["call_id"],
                                "output": json.dumps(result)})
            return {"messages": state["messages"] + outputs, "calls": []}

        graph = StateGraph(GraphState)
        graph.add_node("model", model, retry_policy=None)
        graph.add_node("tools", tools, retry_policy=None)
        graph.add_edge(START, "model")
        graph.add_conditional_edges("model", lambda state: "tools" if state["calls"] else END)
        graph.add_edge("tools", "model")
        async with AsyncSqliteSaver.from_conn_string(str(self.storage / "graph.sqlite")) as saver:
            compiled = graph.compile(checkpointer=saver)
            config = {"configurable": {"thread_id": session_id}, "recursion_limit": 20}
            snapshot = await compiled.aget_state(config)
            messages = snapshot.values.get("messages", [])
            state = await compiled.ainvoke({"messages": messages + [{"role": "user", "content": text}],
                                           "steps": 0, "calls": [], "reply": ""}, config)
            return state["reply"]


ADAPTERS = {"pydanticai": PydanticAdapter, "agents": AgentsAdapter, "langgraph": LangGraphAdapter}
