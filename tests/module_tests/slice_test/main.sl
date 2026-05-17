// End-to-end exercise of slices. main() returns 0 only if every check
// holds, so a regression shows up as a non-zero exit code in the module
// driver. Each failed check has a distinct return value so the failing
// step is identifiable from the exit code alone.

fn i64 sum(i32[] s) {
	i64 total = 0;
	for (i64 i = 0; i < s.len; i = i + 1) {
		total = total + (i64)s[i];
	}
	return total;
}

fn i32 main() {
	i32[5] arr = [10, 20, 30, 40, 50];

	if (arr.len != 5) { return 1; }

	// Array -> slice decay at the call site.
	if (sum(arr) != 150) { return 2; }

	// Array -> slice decay at var-init.
	i32[] s = arr;
	if (s.len != 5) { return 3; }
	if (sum(s) != 150) { return 4; }

	// Index read/write on a slice writes through to the backing array.
	s[0] = 100;
	if (arr[0] != 100) { return 5; }
	if (s[0] != 100) { return 6; }
	if (sum(s) != 240) { return 7; }

	// Sub-slicing an array: arr[1..4] = {20, 30, 40}, length 3.
	i32[] mid = arr[1..4];
	if (mid.len != 3) { return 8; }
	if (mid[0] != 20) { return 9; }
	if (mid[2] != 40) { return 10; }
	if (sum(mid) != 90) { return 11; }

	// Sub-slicing a slice: same backing, length shrinks.
	i32[] inner = mid[1..3];
	if (inner.len != 2) { return 12; }
	if (inner[0] != 30) { return 13; }
	if (sum(inner) != 70) { return 14; }

	// Slice literal: positional and designated forms produce the same
	// view onto the underlying array.
	i32[] sp = {&arr[0], 5};
	if (sp.len != 5) { return 15; }
	if (sum(sp) != 240) { return 16; }

	i32[] sd = {.ptr = &arr[2], .len = 2};
	if (sd.len != 2) { return 17; }
	if (sd[0] != 30) { return 18; }
	if (sd[1] != 40) { return 19; }

	// Null slice: zero data pointer, zero length.
	i32[] empty = null;
	if (empty.len != 0) { return 20; }

	return 0;
}
