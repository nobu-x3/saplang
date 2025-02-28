extern {
    export struct FILE {
        i8*   _ptr;
        i32 _cnt;
        i8*   _base;
        i32 _flag;
        i32 _file;
        i32 _charbuf;
        i32 _bufsiz;
        i8*   _tmpfname;
    }

 
    export fn FILE* fopen(const i8* filename, const i8* mode);

    // returns 0 if closed, EOF otherwise
    export fn i32 fclose(FILE* file);

    export const i32 EOF = -1;

    export fn i32 fprintf(FILE* stream, const i8* format, ...);

    export fn void printf(const i8*, ...);

    export fn i32 fgetc(FILE* stream);
}