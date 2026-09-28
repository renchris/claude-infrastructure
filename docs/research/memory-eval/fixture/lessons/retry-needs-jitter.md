# Retries need jitter

When every client retries on the same schedule they hammer the server at the same moment. Add random jitter to the backoff.
