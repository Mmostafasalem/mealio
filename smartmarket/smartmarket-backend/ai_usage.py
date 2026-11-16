"""Request-local provider outcome, separate from local/cache responses."""
from contextvars import ContextVar

attempted = ContextVar('ai_provider_attempted', default=False)
succeeded = ContextVar('ai_provider_succeeded', default=False)
verified_cache = ContextVar('ai_verified_cache', default=False)
# The provider returned a response (even an unusable one). Distinguishes a
# validation failure, which keeps a small charge, from a transport/provider error.
responded = ContextVar('ai_provider_responded', default=False)
