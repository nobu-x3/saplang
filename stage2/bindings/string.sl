extern {
    fn u8* strcpy (u8* destination, const u8* source );
    fn i32 strcmp (const u8* str1, const u8* str2 );
    fn i32 strncmp (const u8* str1, const u8* str2, i32 num );
}