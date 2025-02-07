export struct<T> GenericStruct {
    T first;
}

export fn GenericStruct<T> gen_fun<T>() {
    var GenericStruct<T> generic_inst = .{69};
    return generic_inst;
}

export fn void init<T>(GenericStruct<T>* inst) {
    inst.first = 0;
}

fn void test_fn() {}
