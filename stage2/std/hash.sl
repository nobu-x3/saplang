
export fn u32 fnv1a_32(const u8[] data) {
    u32 hash = 2166136261;
    for(u64 i = 0; i < data.len; i += 1) {
        hash ^= data[i];
        hash *= 16777619;
    }
    return hash;
}

export fn u64 fnv1a_64(const u8[] data) {
    u64 hash = 14695981039346656037;
    for(u64 i = 0; i < data.len; i += 1) {
        hash ^= data[i];
        hash *= 1099511628211;
    }
    return hash;
}
