#!/usr/bin/env python3
"""Read-only verification that release-validation has real reviewer protection."""
import json
import os
import sys
from urllib.request import Request, urlopen


def protected(data):
    return any(rule.get('type') == 'required_reviewers' and rule.get('reviewers') and
               rule.get('prevent_self_review') is True
               for rule in data.get('protection_rules', []))


def main():
    if os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch' or os.environ.get('GITHUB_REF') != 'refs/heads/main':
        print('::error::Protected release validation requires explicit dispatch on main.')
        return 1
    request = Request(os.environ['GITHUB_API_URL'] + '/repos/' + os.environ['GITHUB_REPOSITORY'] +
                      '/environments/release-validation', headers={
                          'Accept': 'application/vnd.github+json',
                          'Authorization': 'Bearer ' + os.environ['GH_READ_TOKEN'],
                          'X-GitHub-Api-Version': '2026-03-10'})
    try:
        with urlopen(request, timeout=20) as response:
            data = json.load(response)
        if not protected(data):
            raise ValueError('reviewer protection missing')
    except Exception:
        print('::error::Cannot verify release-validation environment protection. Configure required reviewers with prevent self-review and permit read access before dispatching. No distribution is implemented.')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
