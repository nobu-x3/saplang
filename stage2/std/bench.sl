import sys;

// Monotonic nanoseconds; meaningful only as a delta between two calls.
export fn u64 now_ns() {
    return sys::now_ns();
}

export fn u64 time_once(fn* void(void*) f, void* arg) {
    u64 start = now_ns();
    f(arg);
    return now_ns() - start;
}

export struct Stats {
    u64 min;
    u64 median;
    u64 max;
    u64 total;
}

// Runs f(arg) `iters` times, recording each duration into `samples` (len must be >= iters), and returns the summary.
export fn Stats run(fn* void(void*) f, void* arg, u64 iters, u64[] samples) {
    for(u64 i = 0; i < iters; i += 1) {
        samples[i] = time_once(f, arg);
    }
    for(u64 i = 1; i < iters; i += 1) {
        u64 key = samples[i];
        u64 j = i;
        while(j > 0 && samples[j - 1] > key) {
            samples[j] = samples[j - 1];
            j -= 1;
        }
        samples[j] = key;
    }
    Stats st;
    sys::memset(&st, 0, sizeof(Stats));
    if(iters == 0) {
        return st;
    }
    st.min = samples[0];
    st.max = samples[iters - 1];
    st.median = samples[iters / 2];
    for(u64 i = 0; i < iters; i += 1) {
        st.total += samples[i];
    }
    return st;
}
