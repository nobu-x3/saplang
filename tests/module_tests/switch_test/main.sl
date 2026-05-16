// End-to-end exercise of switch / case: int and enum subjects,
// fallthrough labels sharing a body, auto-break after a braced body,
// and the optional `else` clause. main() returns 0 only when every
// branch dispatched to its expected body — a regression in any case
// shows up as a non-zero exit code.

enum Color : i32 { Red, Green, Blue }

fn i32 main() {
    i32 a = 2;
    i32 r = 0;

    // Three labels share one body. Auto-break after the body so r stays at 1.
    switch (a) {
    case 1:
    case 2:
    case 3: { r = 1; }
    case 4: { r = 4; }
    }
    if (r != 1) { return 1; }

    // No matching case: `else` runs.
    a = 10;
    r = 0;
    switch (a) {
    case 1: { r = 1; }
    case 2: { r = 2; }
    else { r = 99; }
    }
    if (r != 99) { return 2; }

    // No matching case, no `else`: nothing runs, r stays.
    a = 7;
    r = 50;
    switch (a) {
    case 1: { r = 1; }
    case 2: { r = 2; }
    }
    if (r != 50) { return 3; }

    // Enum-typed subject.
    Color c = Color::Blue;
    r = 0;
    switch (c) {
    case Color::Red: { r = 100; }
    case Color::Green:
    case Color::Blue: { r = 200; }
    else { r = 300; }
    }
    if (r != 200) { return 4; }

    return 0;
}
