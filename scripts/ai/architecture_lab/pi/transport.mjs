import { AssistantMessageEventStream, getCurrentTools } from '@earendil-works/pi-ai';
import { convertResponsesMessages, convertResponsesTools } from '@earendil-works/pi-ai/api/openai-responses-shared';

export const MODEL = {
  id: 'gpt-6-luna', name: 'GPT-6 Luna', api: 'openai-responses', provider: 'openai',
  baseUrl: 'http://gateway.invalid/v1', reasoning: true, input: ['text'],
  cost: {input: 0.10, output: 0.50, cacheRead: 0.10, cacheWrite: 0.125},
  contextWindow: 128000, maxTokens: 4096,
}; // Context window is an adapter bound, not a provider capability claim.

export function requestPayload(context) {
  return {
    model: MODEL.id,
    input: convertResponsesMessages(MODEL, context, new Set(['openai'])),
    tools: convertResponsesTools(getCurrentTools(context.messages)),
    max_output_tokens: 4096, service_tier: 'default', reasoning: {effort: 'medium'},
    store: false, stream: false,
  };
}

export function gatewayStream(gateway, onResponse = () => {}) {
  return (_model, context, options) => {
    const stream = new AssistantMessageEventStream();
    queueMicrotask(async () => {
      const message = {
        role: 'assistant', content: [], api: MODEL.api, provider: MODEL.provider,
        model: MODEL.id, timestamp: Date.now(), stopReason: 'stop',
        usage: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
          cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0}},
      };
      try {
        const response = await gateway(requestPayload(context), options?.signal);
        onResponse(response);
        if (response.error || !['completed', undefined].includes(response.status)) {
          throw new Error(response.error?.message ?? `Incomplete gateway response: ${response.status}`);
        }
        stream.push({type: 'start', partial: structuredClone(message)});
        for (const item of response.output ?? []) {
          const index = message.content.length;
          if (item.type === 'function_call') {
            const call = {type: 'toolCall', id: item.call_id, name: item.name, arguments: JSON.parse(item.arguments)};
            message.content.push(call);
            stream.push({type: 'toolcall_start', contentIndex: index, partial: structuredClone(message)});
            stream.push({type: 'toolcall_end', contentIndex: index, toolCall: call, partial: structuredClone(message)});
            message.stopReason = 'toolUse';
          } else if (item.type === 'message') {
            for (const content of item.content ?? []) {
              if (content.type !== 'output_text') continue;
              const contentIndex = message.content.length;
              message.content.push({type: 'text', text: content.text});
              stream.push({type: 'text_start', contentIndex, partial: structuredClone(message)});
              stream.push({type: 'text_delta', contentIndex, delta: content.text, partial: structuredClone(message)});
              stream.push({type: 'text_end', contentIndex, content: content.text, partial: structuredClone(message)});
            }
          } else if (item.type !== 'reasoning') {
            throw new Error(`Unsupported Responses output type: ${item.type}`);
          }
        }
        if (!message.content.length) throw new Error('Empty gateway response');
        // Keep opaque reasoning items for the next Responses request, without displaying them.
        const reasoning = (response.output ?? []).filter(item => item.type === 'reasoning');
        if (reasoning.length) message.content.unshift(...reasoning.map(item => ({
          type: 'thinking', thinking: (item.summary ?? []).map(s => s.text ?? '').join('\n'),
          thinkingSignature: JSON.stringify(item),
        })));
        const usage = response.usage;
        if (usage) Object.assign(message.usage, {
          input: usage.input_tokens ?? 0, output: usage.output_tokens ?? 0,
          cacheRead: usage.input_tokens_details?.cached_tokens ?? 0,
          totalTokens: usage.total_tokens ?? 0,
        });
        stream.push({type: 'done', reason: message.stopReason, message});
      } catch (error) {
        message.stopReason = 'error'; message.errorMessage = error.message;
        stream.push({type: 'error', reason: 'error', error: message});
      }
      stream.end();
    });
    return stream;
  };
}

export function httpGateway(url, capability) {
  const parsed = new URL(url);
  if (parsed.protocol !== 'http:' || !['127.0.0.1', '[::1]'].includes(parsed.hostname)
      || parsed.pathname !== '/v1/responses' || parsed.username || parsed.password || parsed.search || parsed.hash) {
    throw new Error('Only the local budget gateway /v1/responses is allowed');
  }
  if (!capability) throw new Error('Local gateway capability is required');
  return async (payload, signal) => {
    const response = await fetch(url, {method: 'POST', redirect: 'error', signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(60000)]) : AbortSignal.timeout(60000),
      headers: {'Content-Type': 'application/json', 'X-Lab-Synthetic': 'true',
        Authorization: `Bearer ${capability}`}, body: JSON.stringify(payload)});
    const body = await response.json();
    if (!response.ok) throw new Error(body.error?.message ?? `Gateway HTTP ${response.status}`);
    if (!body._gateway?.request_id) throw new Error('Missing budget gateway receipt');
    return body;
  };
}
