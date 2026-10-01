/* REDACTED excerpt of kitty v0.49.1 glfw/cocoa_init.m — the tick_lock check-then-use and its shutdown. */
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
    tick_lock = [NSLock new];
    [NSApp run];
    [tick_lock release];
    tick_lock = NULL;
    tick_callback = NULL;
    tick_callback_data = NULL;
}
