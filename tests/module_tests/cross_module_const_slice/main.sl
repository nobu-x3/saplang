import cmcs_lib;

fn i32 main() {
    if(cmcs_lib::TABLE.len != 3) { return 1; }
    if(cmcs_lib::TABLE[1].value != 20) { return 2; }
    if(cmcs_lib::NUMS.len != 4) { return 3; }
    if(cmcs_lib::NUMS[3] != 4) { return 4; }
    return 0;
}
