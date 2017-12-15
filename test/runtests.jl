# This file includes code that was formerly a part of Julia.
# License is MIT: http://julialang.org/license

using Test
using Strs
import Strs: ascii, checkstring, UTF_ERR_SHORT

# Unicode errors
let io = IOBuffer()
    show(io, UnicodeError(UTF_ERR_SHORT, 1, 10))
    check = "UnicodeError: invalid UTF-8 sequence starting at index 1 (0xa) missing one or more continuation bytes)"
    @test String(take!(io)) == check
end

## Test invalid sequences

# Continuation byte not after lead
for byt in 0x80:0xbf
    @test_throws UnicodeError checkstring(UInt8[byt])
end

# Test lead bytes
for byt in 0xc0:0xff
    # Single lead byte at end of string
    @test_throws UnicodeError checkstring(UInt8[byt])
    # Lead followed by non-continuation character < 0x80
    @test_throws UnicodeError checkstring(UInt8[byt,0])
    # Lead followed by non-continuation character > 0xbf
    @test_throws UnicodeError checkstring(UInt8[byt,0xc0])
end

# Test overlong 2-byte
for byt in 0x81:0xbf
    @test_throws UnicodeError checkstring(UInt8[0xc0,byt])
end
for byt in 0x80:0xbf
    @test_throws UnicodeError checkstring(UInt8[0xc1,byt])
end

# Test overlong 3-byte
for byt in 0x80:0x9f
    @test_throws UnicodeError checkstring(UInt8[0xe0,byt,0x80])
end

# Test overlong 4-byte
for byt in 0x80:0x8f
    @test_throws UnicodeError checkstring(UInt8[0xef,byt,0x80,0x80])
end

# Test 4-byte > 0x10ffff
for byt in 0x90:0xbf
    @test_throws UnicodeError checkstring(UInt8[0xf4,byt,0x80,0x80])
end
for byt in 0xf5:0xf7
    @test_throws UnicodeError checkstring(UInt8[byt,0x80,0x80,0x80])
end

# Test 5-byte
for byt in 0xf8:0xfb
    @test_throws UnicodeError checkstring(UInt8[byt,0x80,0x80,0x80,0x80])
end

# Test 6-byte
for byt in 0xfc:0xfd
    @test_throws UnicodeError checkstring(UInt8[byt,0x80,0x80,0x80,0x80,0x80])
end

# Test 7-byte
@test_throws UnicodeError checkstring(UInt8[0xfe,0x80,0x80,0x80,0x80,0x80,0x80])

# Three and above byte sequences
for byt in 0xe0:0xef
    # Lead followed by only 1 continuation byte
    @test_throws UnicodeError checkstring(UInt8[byt,0x80])
    # Lead ended by non-continuation character < 0x80
    @test_throws UnicodeError checkstring(UInt8[byt,0x80,0])
    # Lead ended by non-continuation character > 0xbf
    @test_throws UnicodeError checkstring(UInt8[byt,0x80,0xc0])
end

# 3-byte encoded surrogate character(s)
# Single surrogate
@test_throws UnicodeError checkstring(UInt8[0xed,0xa0,0x80])
# Not followed by surrogate
@test_throws UnicodeError checkstring(UInt8[0xed,0xa0,0x80,0xed,0x80,0x80])
# Trailing surrogate first
@test_throws UnicodeError checkstring(UInt8[0xed,0xb0,0x80,0xed,0xb0,0x80])
# Followed by lead surrogate
@test_throws UnicodeError checkstring(UInt8[0xed,0xa0,0x80,0xed,0xa0,0x80])

# Four byte sequences
for byt in 0xf0:0xf4
    # Lead followed by only 2 continuation bytes
    @test_throws UnicodeError checkstring(UInt8[byt,0x80,0x80])
    # Lead followed by non-continuation character < 0x80
    @test_throws UnicodeError checkstring(UInt8[byt,0x80,0x80,0])
    # Lead followed by non-continuation character > 0xbf
    @test_throws UnicodeError checkstring(UInt8[byt,0x80,0x80,0xc0])
end

# Long encoding of 0x01
@test_throws UnicodeError utf8(b"\xf0\x80\x80\x80")
# Test ends of long encoded surrogates
@test_throws UnicodeError utf8(b"\xf0\x8d\xa0\x80")
@test_throws UnicodeError utf8(b"\xf0\x8d\xbf\xbf")
@test_throws UnicodeError checkstring(b"\xf0\x80\x80\x80")
@test checkstring(b"\xc0\x81"; accept_long_char=true) == (1,0x1,0,0,0)
@test checkstring(b"\xf0\x80\x80\x80"; accept_long_char=true) == (1,0x1,0,0,0)

# Surrogates
@test_throws UnicodeError checkstring(UInt16[0xd800])
@test_throws UnicodeError checkstring(UInt16[0xdc00])
@test_throws UnicodeError checkstring(UInt16[0xdc00,0xd800])

# Surrogates in UTF-32
@test_throws UnicodeError checkstring(UInt32[0xd800])
@test_throws UnicodeError checkstring(UInt32[0xdc00])
@test_throws UnicodeError checkstring(UInt32[0xdc00,0xd800])

# Characters > 0x10ffff
@test_throws UnicodeError checkstring(UInt32[0x110000])

# Test starting and different position
@test checkstring(UInt32[0x110000, 0x1f596], 2) == (1,0x10,1,0,0)

# Test valid sequences
for (seq, res) in (
    (UInt8[0x0],                (1,0,0,0,0)),   # Nul byte, beginning of ASCII range
    (UInt8[0x7f],               (1,0,0,0,0)),   # End of ASCII range
    (UInt8[0xc0,0x80],          (1,1,0,0,0)),   # Long encoded Nul byte (Modified UTF-8, Java)
    (UInt8[0xc2,0x80],          (1,2,0,0,1)),   # \u80, beginning of Latin1 range
    (UInt8[0xc3,0xbf],          (1,2,0,0,1)),   # \uff, end of Latin1 range
    (UInt8[0xc4,0x80],          (1,4,0,0,1)),   # \u100, beginning of non-Latin1 2-byte range
    (UInt8[0xdf,0xbf],          (1,4,0,0,1)),   # \u7ff, end of non-Latin1 2-byte range
    (UInt8[0xe0,0xa0,0x80],     (1,8,0,1,0)),   # \u800, beginning of 3-byte range
    (UInt8[0xed,0x9f,0xbf],     (1,8,0,1,0)),   # \ud7ff, end of first part of 3-byte range
    (UInt8[0xee,0x80,0x80],     (1,8,0,1,0)),   # \ue000, beginning of second part of 3-byte range
    (UInt8[0xef,0xbf,0xbf],     (1,8,0,1,0)),   # \uffff, end of 3-byte range
    (UInt8[0xf0,0x90,0x80,0x80],(1,16,1,0,0)),  # \U10000, beginning of 4-byte range
    (UInt8[0xf4,0x8f,0xbf,0xbf],(1,16,1,0,0)),  # \U10ffff, end of 4-byte range
    (UInt8[0xed,0xa0,0x80,0xed,0xb0,0x80], (1,0x30,1,0,0)), # Overlong \U10000, (CESU-8)
    (UInt8[0xed,0xaf,0xbf,0xed,0xbf,0xbf], (1,0x30,1,0,0)), # Overlong \U10ffff, (CESU-8)
    (UInt16[0x0000],            (1,0,0,0,0)),   # Nul byte, beginning of ASCII range
    (UInt16[0x007f],            (1,0,0,0,0)),   # End of ASCII range
    (UInt16[0x0080],            (1,2,0,0,1)),   # Beginning of Latin1 range
    (UInt16[0x00ff],            (1,2,0,0,1)),   # End of Latin1 range
    (UInt16[0x0100],            (1,4,0,0,1)),   # Beginning of non-Latin1 2-byte range
    (UInt16[0x07ff],            (1,4,0,0,1)),   # End of non-Latin1 2-byte range
    (UInt16[0x0800],            (1,8,0,1,0)),   # Beginning of 3-byte range
    (UInt16[0xd7ff],            (1,8,0,1,0)),   # End of first part of 3-byte range
    (UInt16[0xe000],            (1,8,0,1,0)),   # Beginning of second part of 3-byte range
    (UInt16[0xffff],            (1,8,0,1,0)),   # End of 3-byte range
    (UInt16[0xd800,0xdc00],     (1,16,1,0,0)),  # \U10000, beginning of 4-byte range
    (UInt16[0xdbff,0xdfff],     (1,16,1,0,0)),  # \U10ffff, end of 4-byte range
    (UInt32[0x0000],            (1,0,0,0,0)),   # Nul byte, beginning of ASCII range
    (UInt32[0x007f],            (1,0,0,0,0)),   # End of ASCII range
    (UInt32[0x0080],            (1,2,0,0,1)),   # Beginning of Latin1 range
    (UInt32[0x00ff],            (1,2,0,0,1)),   # End of Latin1 range
    (UInt32[0x0100],            (1,4,0,0,1)),   # Beginning of non-Latin1 2-byte range
    (UInt32[0x07ff],            (1,4,0,0,1)),   # End of non-Latin1 2-byte range
    (UInt32[0x0800],            (1,8,0,1,0)),   # Beginning of 3-byte range
    (UInt32[0xd7ff],            (1,8,0,1,0)),   # End of first part of 3-byte range
    (UInt32[0xe000],            (1,8,0,1,0)),   # Beginning of second part of 3-byte range
    (UInt32[0xffff],            (1,8,0,1,0)),   # End of 3-byte range
    (UInt32[0x10000],           (1,16,1,0,0)),  # \U10000, beginning of 4-byte range
    (UInt32[0x10ffff],          (1,16,1,0,0)),  # \U10ffff, end of 4-byte range
    (UInt32[0xd800,0xdc00],     (1,0x30,1,0,0)),# Overlong \U10000, (CESU-8)
    (UInt32[0xdbff,0xdfff],     (1,0x30,1,0,0)))# Overlong \U10ffff, (CESU-8)
    @test checkstring(seq) == res
end

# Test bounds checking
@test_throws BoundsError checkstring(b"abcdef", -10)
@test_throws BoundsError checkstring(b"abcdef", 0)
@test_throws BoundsError checkstring(b"abcdef", 7)
@test_throws BoundsError checkstring(b"abcdef", 3, -10)
@test_throws BoundsError checkstring(b"abcdef", 3, 0)
@test_throws BoundsError checkstring(b"abcdef", 3, 7)
@test_throws ArgumentError checkstring(b"abcdef", 3, 1)

## UTF-8 tests

# Test for CESU-8 sequences
let ch = 0x10000
    for hichar = 0xd800:0xdbff
        for lochar = 0xdc00:0xdfff
            @test convert(UTF8Str, utf8(Char[hichar, lochar]).data) == string(Char(ch))
            ch += 1
        end
    end
end

let str = UTF8Str(b"this is a test\xed\x80")
    @test next(str, 15) == ('\ufffd', 16)
    @test_throws BoundsError getindex(str, 0:3)
    @test_throws BoundsError getindex(str, 17:18)
    @test_throws BoundsError getindex(str, 2:17)
    @test_throws UnicodeError getindex(str, 16:17)
    @test string(Char(0x110000)) == "\ufffd"
    sa = SubString{ASCIIStr}(ascii("This is a silly test"), 1, 14)
    s8 = convert(SubString{UTF8Str}, sa)
    @test typeof(s8) == SubString{UTF8Str}
    @test s8 == "This is a sill"
    @test convert(UTF8Str, b"this is a test\xed\x80\x80") == "this is a test\ud000"
end

# Reverse of UTF8Str
@test reverse(UTF8Str("")) == ""
@test reverse(UTF8Str("a")) == "a"
@test reverse(UTF8Str("abc")) == "cba"
@test reverse(UTF8Str("xyz\uff\u800\uffff\U10ffff")) == "\U10ffff\uffff\u800\uffzyx"
for str in (b"xyz\xc1", b"xyz\xd0", b"xyz\xe0", b"xyz\xed\x80", b"xyz\xf0", b"xyz\xf0\x80",  b"xyz\xf0\x80\x80")
    @test_throws UnicodeError reverse(UTF8Str(str))
end

# Specifically check UTF-8 string whose lead byte is same as a surrogate
@test convert(UTF8Str,b"\xed\x9f\xbf") == "\ud7ff"

# issue #8
@test !isempty(methods(string, Tuple{Char}))

## UTF-16 tests

u8 = "\U10ffff\U1d565\U1d7f6\U00066\U2008a"
u16 = utf16(u8)
@test sizeof(u16) == 18
@test length(u16.data) == 10 && u16.data[end] == 0
@test length(u16) == 5
@test utf8(u16) == u8
@test collect(u8) == collect(u16)
@test u8 == utf16(u16.data[1:end-1]) == utf16(copy!(Vector{UInt8}(18), 1, reinterpret(UInt8, u16.data), 1, 18))
@test u8 == utf16(pointer(u16)) == utf16(convert(Ptr{Int16}, pointer(u16)))
@test_throws UnicodeError utf16(utf32(Char(0x120000)))
@test_throws UnicodeError utf16(UInt8[1,2,3])

@test convert(UTF16Str, "test") == "test"
@test convert(UTF16Str, u16) == u16
@test convert(UTF16Str, UInt16[[0x65, 0x66] [0x67, 0x68]]) == "efgh"
@test convert(UTF16Str, Int16[[0x65, 0x66] [0x67, 0x68]]) == "efgh"
@test map(lowercase, utf16("TEST\U1f596")) == "test\U1f596"
@test typeof(Base.unsafe_convert(Ptr{UInt16}, utf16("test"))) == Ptr{UInt16}

## UTF-32 tests

u8 = "\U10ffff\U1d565\U1d7f6\U00066\U2008a"
u32 = utf32(u8)
@test sizeof(u32) == 20
@test length(u32.data) == 6 && u32.data[end] == 0
@test length(u32) == 5
@test utf8(u32) == u8
@test collect(u8) == collect(u32)
@test u8 == utf32(u32.data[1:end-1]) == utf32(copy!(Vector{UInt8}(20), 1, reinterpret(UInt8, u32.data), 1, 20))
@test u8 == utf32(pointer(u32)) == utf32(convert(Ptr{Int32}, pointer(u32)))
@test_throws UnicodeError utf32(UInt8[1,2,3])

# issue #11551 (#11004,#10959)
function tstcvt(strUTF8::UTF8Str, strUTF16::UTF16Str, strUTF32::UTF32Str)
    @test utf16(strUTF8) == strUTF16
    @test utf32(strUTF8) == strUTF32
    @test utf8(strUTF16) == strUTF8
    @test utf32(strUTF16) == strUTF32
    @test utf8(strUTF32)  == strUTF8
    @test utf16(strUTF32) == strUTF16
end

# Create some ASCII, UTF8, UTF16, and UTF32 strings
strAscii = ascii("abcdefgh")
strA_UTF8 = utf8(("abcdefgh\uff")[1:8])
strL_UTF8 = utf8("abcdef\uff\uff")
str2_UTF8 = utf8("abcd\uff\uff\u7ff\u7ff")
str3_UTF8 = utf8("abcd\uff\uff\u7fff\u7fff")
str4_UTF8 = utf8("abcd\uff\u7ff\u7fff\U7ffff")
strS_UTF8 = UTF8Str(b"abcd\xc3\xbf\xdf\xbf\xe7\xbf\xbf\xed\xa0\x80\xed\xb0\x80")
strC_UTF8 = UTF8Str(b"abcd\xc3\xbf\xdf\xbf\xe7\xbf\xbf\U10000")
strz_UTF8 = UTF8Str(b"abcd\xc3\xbf\xdf\xbf\xe7\xbf\xbf\0")
strZ      = b"abcd\xc3\xbf\xdf\xbf\xe7\xbf\xbf\xc0\x80"

strA_UTF16 = utf16(strA_UTF8)
strL_UTF16 = utf16(strL_UTF8)
str2_UTF16 = utf16(str2_UTF8)
str3_UTF16 = utf16(str3_UTF8)
str4_UTF16 = utf16(str4_UTF8)
strS_UTF16 = utf16(strS_UTF8)

strA_UTF32 = utf32(strA_UTF8)
strL_UTF32 = utf32(strL_UTF8)
str2_UTF32 = utf32(str2_UTF8)
str3_UTF32 = utf32(str3_UTF8)
str4_UTF32 = utf32(str4_UTF8)
strS_UTF32 = utf32(strS_UTF8)

@test utf8(strAscii) == strAscii
@test utf16(strAscii) == strAscii
@test utf32(strAscii) == strAscii

tstcvt(strA_UTF8,strA_UTF16,strA_UTF32)
tstcvt(strL_UTF8,strL_UTF16,strL_UTF32)
tstcvt(str2_UTF8,str2_UTF16,str2_UTF32)
tstcvt(str3_UTF8,str3_UTF16,str3_UTF32)
tstcvt(str4_UTF8,str4_UTF16,str4_UTF32)

# Test converting surrogate pairs
@test utf16(strS_UTF8) == strC_UTF8
@test utf32(strS_UTF8) == strC_UTF8
@test utf8(strS_UTF16) == strC_UTF8
@test utf32(strS_UTF16) == strC_UTF8
@test utf8(strS_UTF32)  == strC_UTF8
@test utf16(strS_UTF32) == strC_UTF8

# Test converting overlong \0
@test utf8(strZ)  == strz_UTF8
@test utf16(UTF8Str(strZ)) == strz_UTF8
@test utf32(UTF8Str(strZ)) == strz_UTF8

# Test invalid sequences

strval(::Type{UTF8Str}, dat) = dat
strval(::Union{Type{UTF16Str},Type{UTF32Str}}, dat) = UTF8Str(dat)

for T in (UTF8Str, UTF16Str, UTF32Str)
    # Continuation byte not after lead
    for byt in 0x80:0xbf
        @test_throws UnicodeError convert(T,  strval(T, UInt8[byt]))
    end

    # Test lead bytes
    for byt in 0xc0:0xff
        # Single lead byte at end of string
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt]))
        # Lead followed by non-continuation character < 0x80
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0]))
        # Lead followed by non-continuation character > 0xbf
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0xc0]))
    end

    # Test overlong 2-byte
    for byt in 0x81:0xbf
        @test_throws UnicodeError convert(T, strval(T, UInt8[0xc0,byt]))
    end
    for byt in 0x80:0xbf
        @test_throws UnicodeError convert(T, strval(T, UInt8[0xc1,byt]))
    end

    # Test overlong 3-byte
    for byt in 0x80:0x9f
        @test_throws UnicodeError convert(T, strval(T, UInt8[0xe0,byt,0x80]))
    end

    # Test overlong 4-byte
    for byt in 0x80:0x8f
        @test_throws UnicodeError convert(T, strval(T, UInt8[0xef,byt,0x80,0x80]))
    end

    # Test 4-byte > 0x10ffff
    for byt in 0x90:0xbf
        @test_throws UnicodeError convert(T, strval(T, UInt8[0xf4,byt,0x80,0x80]))
    end
    for byt in 0xf5:0xf7
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0x80,0x80,0x80]))
    end

    # Test 5-byte
    for byt in 0xf8:0xfb
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0x80,0x80,0x80,0x80]))
    end

    # Test 6-byte
    for byt in 0xfc:0xfd
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0x80,0x80,0x80,0x80,0x80]))
    end

    # Test 7-byte
    @test_throws UnicodeError convert(T, strval(T, UInt8[0xfe,0x80,0x80,0x80,0x80,0x80,0x80]))

    # Three and above byte sequences
    for byt in 0xe0:0xef
        # Lead followed by only 1 continuation byte
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0x80]))
        # Lead ended by non-continuation character < 0x80
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0x80,0]))
        # Lead ended by non-continuation character > 0xbf
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0x80,0xc0]))
    end

    # 3-byte encoded surrogate character(s)
    # Single surrogate
    @test_throws UnicodeError convert(T, strval(T, UInt8[0xed,0xa0,0x80]))
    # Not followed by surrogate
    @test_throws UnicodeError convert(T, strval(T, UInt8[0xed,0xa0,0x80,0xed,0x80,0x80]))
    # Trailing surrogate first
    @test_throws UnicodeError convert(T, strval(T, UInt8[0xed,0xb0,0x80,0xed,0xb0,0x80]))
    # Followed by lead surrogate
    @test_throws UnicodeError convert(T, strval(T, UInt8[0xed,0xa0,0x80,0xed,0xa0,0x80]))

    # Four byte sequences
    for byt in 0xf0:0xf4
        # Lead followed by only 2 continuation bytes
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0x80,0x80]))
        # Lead followed by non-continuation character < 0x80
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0x80,0x80,0]))
        # Lead followed by non-continuation character > 0xbf
        @test_throws UnicodeError convert(T, strval(T, UInt8[byt,0x80,0x80,0xc0]))
    end
end

# Wstring
u8 = "\U10ffff\U1d565\U1d7f6\U00066\U2008a"
w = wstring(u8)
@test length(w) == 5 && utf8(w) == u8 && collect(u8) == collect(w)
@test u8 == WString(w.data)

# 12268
for (fun, S, T) in ((utf16, UInt16, UTF16Str), (utf32, UInt32, UTF32Str))
    # AbstractString
    str = "abcd\0\uff\u7ff\u7fff\U7ffff"
    tst = SubString(convert(T,str),4)
    cmp = Char['d','\0','\uff','\u7ff','\u7fff','\U7ffff']
    cmp32 = UInt32['d','\0','\uff','\u7ff','\u7fff','\U7ffff','\0']
    cmp16 = UInt16[0x0064,0x0000,0x00ff,0x07ff,0x7fff,0xd9bf,0xdfff,0x0000]
    x = fun(tst)
    cmpx = (S == UInt16 ? cmp16 : cmp32)
    @test typeof(tst) == SubString{T}
    @test convert(T, tst) == str[4:end]
    @test Vector{Char}(x) == cmp
    # Vector{T} / Array{T}
    @test convert(Vector{S}, x) == cmpx
    @test convert(Array{S}, x) == cmpx
    # Embedded nul checking
    @test Base.containsnul(x)
    @test Base.containsnul(tst)
    # map
    @test_throws UnicodeError map(islower, x)
    @test_throws ArgumentError map(islower, tst)
    # SubArray conversion
    subarr = view(cmp, 1:6)
    @test convert(T, subarr) == str[4:end]
end

# Char to UTF32Str
@test utf32('\U7ffff') == utf32("\U7ffff")
@test convert(UTF32Str, '\U7ffff') == utf32("\U7ffff")

@test isvalid(UTF32Str, Char['d','\uff','\u7ff','\u7fff','\U7ffff'])
@test reverse(utf32("abcd \uff\u7ff\u7fff\U7ffff")) == utf32("\U7ffff\u7fff\u7ff\uff dcba")

# Test pointer() functions
let str = ascii("this ")
    u8  = utf8(str)
    u16 = utf16(str)
    u32 = utf32(str)
    pa  = pointer(str)
    p8  = pointer(u8)
    p16 = pointer(u16)
    p32 = pointer(u32)
    @test typeof(pa) == Ptr{UInt8}
    @test unsafe_load(pa,1) == 0x74
    @test typeof(p8) == Ptr{UInt8}
    @test unsafe_load(p8,1) == 0x74
    @test typeof(p16) == Ptr{UInt16}
    @test unsafe_load(p16,1) == 0x74
    @test typeof(p32) == Ptr{UInt32}
    @test unsafe_load(p32,1) == 0x74
    pa  = pointer(str, 2)
    p8  = pointer(u8,  2)
    p16 = pointer(u16, 2)
    p32 = pointer(u32, 2)
    @test typeof(pa) == Ptr{UInt8}
    @test unsafe_load(pa,1) == 0x68
    @test typeof(p8) == Ptr{UInt8}
    @test unsafe_load(p8,1) == 0x68
    @test typeof(p16) == Ptr{UInt16}
    @test unsafe_load(p16,1) == 0x68
    @test typeof(p32) == Ptr{UInt32}
    @test unsafe_load(p32,1) == 0x68
    sa  = SubString{ASCIIStr}(str, 3, 5)
    s8  = SubString{UTF8Str}(u8,   3, 5)
    s16 = SubString{UTF16Str}(u16, 3, 5)
    s32 = SubString{UTF32Str}(u32, 3, 5)
    pa  = pointer(sa)
    p8  = pointer(s8)
    p16 = pointer(s16)
    p32 = pointer(s32)
    @test typeof(pa) == Ptr{UInt8}
    @test unsafe_load(pa,1) == 0x69
    @test typeof(p8) == Ptr{UInt8}
    @test unsafe_load(p8,1) == 0x69
    @test typeof(p16) == Ptr{UInt16}
    @test unsafe_load(p16,1) == 0x69
    @test typeof(p32) == Ptr{UInt32}
    @test unsafe_load(p32,1) == 0x69
    pa  = pointer(sa, 2)
    p8  = pointer(s8,  2)
    p16 = pointer(s16, 2)
    p32 = pointer(s32, 2)
    @test typeof(pa) == Ptr{UInt8}
    @test unsafe_load(pa,1) == 0x73
    @test typeof(p8) == Ptr{UInt8}
    @test unsafe_load(p8,1) == 0x73
    @test typeof(p16) == Ptr{UInt16}
    @test unsafe_load(p16,1) == 0x73
    @test typeof(p32) == Ptr{UInt32}
    @test unsafe_load(p32,1) == 0x73
end
