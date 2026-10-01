/* The v0.49.1 excerpt with the drafted fix: the lock is created once and never released or NULLed,
 * so the child-monitor thread can never message a freed object. */
static NSLock *tick_lock = NULL;

void
_glfwPlatformPostEmptyEvent(void) {
    if (pthread_equal(pthread_self(), main_thread)) {
        request_tick_callback();
    } else if (tick_lock) {
        [tick_lock lock];
        request_tick_callback();
        [tick_lock unlock];
    }
}

void
_glfwPlatformRunMainLoop(GLFWtickcallback callback, void *data) {
    main_thread = pthread_self();
    tick_callback = callback;
    tick_callback_data = data;
    if (!tick_lock) tick_lock = [NSLock new];
    [NSApp run];
    tick_callback = NULL;
    tick_callback_data = NULL;
}
