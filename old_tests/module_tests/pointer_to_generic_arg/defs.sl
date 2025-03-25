extern {
    fn void* malloc(i64 size);
}

export struct<T> GenericStruct {
    T first;
}

export fn GenericStruct<T>* gen_fun<T>() {
    var GenericStruct<T>* generic_inst = malloc(sizeof(GenericStruct<T>));
    generic_inst.first = 69;
    return generic_inst;
}

export fn void init<T>(GenericStruct<T>* inst) {
    inst.first = 0;
}
