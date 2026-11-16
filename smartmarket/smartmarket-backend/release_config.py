"""Fail-closed production configuration checks. Reports names, never secret values."""
import os

DEFAULT_MODEL = 'openai/gpt-oss-120b'
RETIRED_CONSUMER_MODELS = {'llama-3.3-70b-versatile','llama-3.1-8b-instant'}


def production_errors(config, accounts_ready=False):
    errors=[]
    key=config.get('APP_API_KEY','')
    if (not isinstance(key,str) or len(key)<32 or not key.isascii()
            or key.lower().startswith(('your_','placeholder','test'))):
        errors.append('APP_API_KEY')
    enabled=config.get('AI_ACCOUNTS_ENABLED')
    if enabled not in {'0','1'}: errors.append('AI_ACCOUNTS_ENABLED')
    if config.get('GROQ_MODEL',DEFAULT_MODEL) in RETIRED_CONSUMER_MODELS:
        errors.append('GROQ_MODEL')
    if enabled == '1':
        provider=config.get('GROQ_API_KEY','')
        if not isinstance(provider,str) or not provider.startswith('gsk_') or len(provider)<24:
            errors.append('GROQ_API_KEY')
        if not accounts_ready: errors.append('AI_ACCOUNTS_READY')
    return errors


if __name__ == '__main__':
    import json
    from ai_accounts import AccountService
    try: ready=AccountService.from_env() is not None
    except Exception: ready=False
    errors=production_errors(os.environ,accounts_ready=ready)
    print(json.dumps({'ready':not errors,'missingOrInvalid':errors}))
    raise SystemExit(bool(errors))
