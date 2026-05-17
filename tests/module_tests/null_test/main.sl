// End-to-end exercise of the `null` literal. main() returns 0 on
// success and a distinct non-zero code at each failed expectation so a
// regression shows up in the module-test driver's exit-code check.

fn i32* always_null() { return null; }

struct Node {
    i32 value;
    Node* next;
}

fn i32 main() {
    i32* p = null;
    if (p != null) { return 1; }
    if (p == null) {} else { return 2; }
    if (p) { return 3; }
    if (!p) {} else { return 4; }

    i32 v = 42;
    i32* q = &v;
    if (q == null) { return 5; }
    if (q != null) {} else { return 6; }
    if (q) {} else { return 7; }
    if (!q) { return 8; }

    q = null;
    if (q != null) { return 9; }
    if (!q) {} else { return 10; }

    i32* r = always_null();
    if (r != null) { return 11; }

    Node n = {.value = 1, .next = null};
    if (n.next != null) { return 12; }

    Node n2 = {2, null};
    if (n2.next != null) { return 13; }

    return 0;
}
