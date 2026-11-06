"""Explicit operator-only synthetic inference check; never prints keys or content."""
import argparse
import os


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live',action='store_true',help='Make one real synthetic provider request (uses provider quota)')
    args=parser.parse_args()
    if not args.live:
        parser.error('Pass --live to explicitly authorize the provider request.')
    if not os.environ.get('GROQ_API_KEY'):
        print('GROQ_API_KEY is missing. Set it locally or in the hosting dashboard, never in chat.')
        return 2
    import app
    import ai_usage
    ai_usage.attempted.set(False);ai_usage.succeeded.set(False)
    result=app.groq_json([{'role':'user','content':'Return ONLY JSON: {"ready":true}'}],
                         fallback=None,max_tokens=128,json_object=True,
                         validator=lambda value:isinstance(value,dict) and value.get('ready') is True)
    success=ai_usage.succeeded.get() and result == {'ready':True}
    print('Provider inference: '+('ONLINE' if success else 'FAILED / FALLBACK'))
    print('Model: '+app.GROQ_MODEL)
    return 0 if success else 1


if __name__ == '__main__': raise SystemExit(main())
