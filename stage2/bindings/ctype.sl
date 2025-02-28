extern {
    fn i32 isspace(i32 c);
    fn i32 isalnum(i32 c);
    fn i32 isalpha(i32 c);
    fn i32 isblank (i32 c);
    fn i32 iscntrl (i32 c);
    fn i32 isdigit (i32 c);
    fn i32 isgraph (i32 c);
    fn i32 islower (i32 c);
    fn i32 isprint (i32 c);
    fn i32 ispunct (i32 c);
    fn i32 isupper (i32 c);
    fn i32 isxdigit (i32 c);

    fn i32 tolower(i32 c);
    fn i32 toupper(i32 c);
}