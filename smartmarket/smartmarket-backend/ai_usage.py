"""Request-local provider outcome, separate from local/cache responses."""
from contextvars import ContextVar

attempted = ContextVar('ai_provider_attempted', default=False)
succeeded = ContextVar('ai_provider_succeeded', default=False)
verified_cache = ContextVar('ai_verified_cache', default=False)
