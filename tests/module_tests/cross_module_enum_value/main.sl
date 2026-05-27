import colors;

fn i32 use_in_arg(colors::Color c) {
    if (c == colors::Color::Green) { return 7; }
    if (c == colors::Color::Blue)  { return 8; }
    return 0;
}

fn i32 main() {
    colors::Color c = colors::Color::Green;
    if (use_in_arg(c) != 7) { return 1; }

    i32 v = (i32)colors::Color::Blue;
    if (v != 8) { return 2; }

    switch (c) {
    case colors::Color::Red:   { return 3; }
    case colors::Color::Green: { }
    case colors::Color::Blue:  { return 4; }
    else { return 5; }
    }
    return 0;
}
