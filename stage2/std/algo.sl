export fn void swap(comptime Type T, T* a, T* b) {
    T tmp = *a;
    *a = *b;
    *b = tmp;
}

export fn void sort(comptime Type T, T[] data, fn* bool(T, T) less) {
    while(data.len > 1) {
        u64 split = partition(data, less);
        T[] lesser = data[0..(split + 1)];
        T[] greater = data[(split + 1)..data.len];
        if(lesser.len < greater.len) {
            sort(lesser, less);
            data = greater;
        } else {
            sort(greater, less);
            data = lesser;
        }
    }
}

fn u64 partition(comptime Type T, T[] data, fn* bool(T, T) less) {
    T pivot = data[(data.len - 1) / 2];
    u64 lo = 0;
    u64 hi = data.len - 1;
    while(true) {
        while(less(data[lo], pivot)) { lo += 1; }
        while(less(pivot, data[hi])) { hi -= 1; }
        if(lo >= hi) { return hi; }
        swap(&data[lo], &data[hi]);
        lo += 1;
        hi -= 1;
    }
    return hi;
}
