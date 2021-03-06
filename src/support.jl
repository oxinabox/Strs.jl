# Based partly on code in LegacyStrings that used to be part of Julia
# Licensed under MIT License, see LICENSE.md

# (Mostly written by Scott P. Jones in series of PRs contributed to the Julia project in 2015)

## Error messages for Unicode / UTF support

const UTF_ERR_SHORT =
  "invalid UTF-8 sequence starting at index <<1>> (0x<<2>>) missing one or more continuation bytes"
const UTF_ERR_CONT =
  "invalid UTF-8 sequence starting at index <<1>> (0x<<2>>) is not a continuation byte"
const UTF_ERR_LONG =
  "invalid UTF-8 sequence, overlong encoding starting at index <<1>> (0x<<2>>)"
const UTF_ERR_NOT_LEAD =
  "not a leading Unicode surrogate code unit at index <<1>> (0x<<2>>)"
const UTF_ERR_NOT_TRAIL =
  "not a trailing Unicode surrogate code unit at index <<1>> (0x<<2>>)"
const UTF_ERR_NOT_SURROGATE =
  "not a valid Unicode surrogate code unit at index <<1>> (0x<<2>>)"
const UTF_ERR_MISSING_SURROGATE =
  "missing trailing Unicode surrogate code unit after index <<1>> (0x<<2>>)"
const UTF_ERR_INVALID =
  "invalid Unicode character starting at index <<1>> (0x<<2>> > 0x10ffff)"
const UTF_ERR_SURROGATE =
  "surrogate encoding not allowed in UTF-8 or UTF-32, at index <<1>> (0x<<2>>)"
const UTF_ERR_ODD_BYTES_16 =
  "UTF16String can't have odd number of bytes <<1>>"
const UTF_ERR_ODD_BYTES_32 =
  "UTF32String must have multiple of 4 bytes <<1>>"
const UTF_ERR_INVALID_ASCII =
  "invalid ASCII character at index <<1>> (0x<<2>> > 0x7f)"
const UTF_ERR_INVALID_LATIN1 =
  "invalid Latin1 character at index <<1>> (0x<<2>> > 0xff)"
const UTF_ERR_INVALID_CHAR =
  "invalid Unicode character (0x<<2>> > 0x10ffff)"
const UTF_ERR_INVALID_8 =
  "invalid UTF-8 data"
const UTF_ERR_INVALID_16 =
  "invalid UTF-16 data"
const UTF_ERR_INVALID_UCS2 =
  "invalid UCS-2 character (surrogate present)"
const UTF_ERR_INVALID_INDEX =
  "invalid character index <<1>>"

@static if isdefined(Base, :UnicodeError)
    Base.UnicodeError(msg) = UnicodeError(msg, 0%Int32, 0%UInt32)
else

struct UnicodeError <: Exception
    errmsg::AbstractString   ##< A UTF_ERR_ message
    errpos::Int32            ##< Position of invalid character
    errchr::UInt32           ##< Invalid character
    UnicodeError(msg, pos, chr) = new(msg, pos%Int32, chr%UInt32)
    UnicodeError(msg) = new(msg, 0%Int32, 0%UInt32)
end

_repmsg(msg, pos, chr) =
    replace(replace(msg, "<<1>>" => string(pos)), "<<2>>" =>  outhex(chr))
show(io::IO, exc::UnicodeError) =
    print(io, "UnicodeError: ", _repmsg(exc.errmsg, exc.errpos, exc.errchr))
end

const UTF_ERR_DECOMPOSE_COMPOSE = "only one of decompose or compose may be true"
const UTF_ERR_COMPAT_STRIPMARK  = "compat or stripmark true requires compose or decompose true"
const UTF_ERR_NL_CONVERSION     = "only one newline conversion may be specified"
const UTF_ERR_NORMALIZE         = " is not one of :NFC, :NFD, :NFKC, :NFKD"

@noinline boundserr(s, pos)      = throw(BoundsError(s, pos))
@noinline unierror(err)          = throw(UnicodeError(err))
@noinline unierror(err, pos, ch) = throw(UnicodeError(err, pos, ch))
@noinline unierror(err, v)       = unierror(string(":", v, err))
@noinline nulerr()               = unierror("cannot convert NULL to string")
@noinline neginderr(s, n)        = unierror("Index ($n) must be non negative")
@noinline codepoint_error(T, v)  = unierror(string("Invalid CodePoint: ", T, " 0x", outhex(v)))
@noinline argerror(startpos, endpos) =
    unierror(string("End position ", endpos, " is less than start position (", startpos, ")"))

@noinline ascii_err()    = throw(ArgumentError("Not a valid ASCII string"))
@noinline ncharerr(n)    = throw(ArgumentError(string("nchar (", n, ") must be not be negative")))
@noinline repeaterr(cnt) = throw(ArgumentError("repeat count $cnt must be >= 0"))

@static isdefined(Base, :string_index_err) && (const index_error = Base.string_index_err)

## Functions to check validity of UTF-8, UTF-16, and UTF-32 encoded strings,
#  and also to return information necessary to convert to other encodings

is_surrogate_lead(c::Unsigned) = ((c & ~0x003ff) == 0xd800)
is_surrogate_trail(c::Unsigned) = ((c & ~0x003ff) == 0xdc00)
is_surrogate_codeunit(c::Unsigned) = ((c & ~0x007ff) == 0xd800)
is_valid_continuation(c) = ((c & 0xc0) == 0x80)

## Return flags for check_string function

const UTF_LONG      =  1  ##< Long encodings are present
const UTF_LATIN1    =  2  ##< characters in range 0x80-0xFF present
const UTF_UNICODE2  =  4  ##< characters in range 0x100-0x7ff present
const UTF_UNICODE3  =  8  ##< characters in range 0x800-0xd7ff, 0xe000-0xffff
const UTF_UNICODE4  = 16  ##< non-BMP characters present
const UTF_SURROGATE = 32  ##< surrogate pairs present
const UTF_INVALID   = 64  ##< invalid sequences present

# Get a UTF-8 continuation byte, give error if invalid, return updated character value
@propagate_inbounds function check_continuation(dat, pos, ch, flag)
    @inbounds byt = get_codeunit(dat, pos)
    pos += 1
    if is_valid_continuation(byt)
        flag = false
    elseif !flag
        unierror(UTF_ERR_CONT, pos, byt)
    end
    (ch%UInt32 << 6) | (byt & 0x3f), pos, flag
end

"""
Validates and calculates number of characters in a UTF-8,UTF-16 or UTF-32 encoded vector/string

Warning: this function does not check the bounds of the start or end positions
Use `check_string` to make sure the bounds are checked

Input Arguments:

* `dat`    UTF-8 (`Vector{UInt8}`), UTF-16 (`Vector{UInt16}`) or UTF-32 (`Vector{UInt32}`, `AbstractString`) encoded string
* `pos`    start position
* `endpos` end position

Keyword Arguments:

* `accept_long_null`  = `false`  # Modified UTF-8 (`\\0` represented as `b\"\\xc0\\x80\"`)
* `accept_surrogates` = `false`  # `CESU-8`
* `accept_long_char`  = `false`  # Accept arbitrary long encodings
* `accept_invalids`   = `false`  # Accept invalid sequences (to be replaced on conversion)

Returns:

* (total characters, flags, 4-byte, 3-byte, 2-byte)

Throws:

* `UnicodeError`
"""
function unsafe_check_string end

_ret_check(totalchar, flags, invalids, latin1byte, num2byte, num3byte, num4byte) =
    (totalchar,
     ifelse(latin1byte == 0, 0, UTF_LATIN1) |
     ifelse(num2byte   == 0, 0, UTF_UNICODE2) |
     ifelse(num3byte   == 0, 0, UTF_UNICODE3) |
     ifelse(num4byte   == 0, 0, UTF_UNICODE4) |
     ifelse(invalids   == 0, 0, UTF_INVALID) | flags,
     num4byte, num3byte, num2byte, latin1byte, invalids)

function unsafe_check_string(dat::T, pos, endpos;
                             accept_long_null  = false,
                             accept_surrogates = false,
                             accept_long_char  = false,
                             accept_invalids   = false
                             ) where {T<:Union{AbstractVector{UInt8}, Ptr{UInt8}, String}}
    flags = 0%UInt
    totalchar = latin1byte = num2byte = num3byte = num4byte = invalids = 0
    @inbounds while pos <= endpos
        ch = get_codeunit(dat, pos)
        pos += 1
        totalchar += 1
        if ch > 0x7f
            # Check UTF-8 encoding
            if ch < 0xe0
                # 2-byte UTF-8 sequence (i.e. characters 0x80-0x7ff)
                if pos > endpos
                    accept_invalids || unierror(UTF_ERR_SHORT, pos, ch)
                    invalids += 1
                    break
                end
                ch, pos, flg = check_continuation(dat, pos, ch & 0x3f, accept_invalids)
                flg && (invalids += 1 ; continue)
                if ch > 0xff
                    num2byte += 1
                elseif ch > 0x7f
                    latin1byte += 1
                elseif accept_long_char
                    flags |= UTF_LONG
                elseif (ch == 0) && accept_long_null
                    flags |= UTF_LONG
                elseif accept_invalids
                    invalids += 1
                else
                    unierror(UTF_ERR_LONG, pos, ch)
                end
             elseif ch < 0xf0
                # 3-byte UTF-8 sequence (i.e. characters 0x800-0xffff)
                if pos + 1 > endpos
                    accept_invalids || unierror(UTF_ERR_SHORT, pos, ch)
                    invalids += 1
                    break
                end
                ch, pos, flg = check_continuation(dat, pos, ch & 0x0f, accept_invalids)
                flg && (invalids += 1 ; continue)
                ch, pos, flg = check_continuation(dat, pos, ch, accept_invalids)
                flg && (invalids += 1 ; continue)
                # check for surrogate pairs, make sure correct
                if is_surrogate_codeunit(ch)
                    if !is_surrogate_lead(ch)
                        accept_invalids || unierror(UTF_ERR_NOT_LEAD, pos-2, ch)
                        invalids += 1
                        continue
                    end
                    # next character *must* be a trailing surrogate character
                    if pos + 2 > endpos
                        accept_invalids || unierror(UTF_ERR_MISSING_SURROGATE, pos-2, ch)
                        invalids += 1
                        break
                    end
                    byt = get_codeunit(dat, pos)
                    pos += 1
                    if byt != 0xed
                        accept_invalids || unierror(UTF_ERR_NOT_TRAIL, pos, byt)
                        invalids += 1
                        continue
                    end
                    surr, pos, flg = check_continuation(dat, pos, 0x0000d, accept_invalids)
                    flg && (invalids += 1 ; continue)
                    surr, pos, flg = check_continuation(dat, pos, surr, accept_invalids)
                    flg && (invalids += 1 ; continue)
                    if !is_surrogate_trail(surr)
                        accept_invalids || unierror(UTF_ERR_NOT_TRAIL, pos-2, surr)
                        invalids += 1
                    elseif !accept_surrogates
                        accept_invalids || unierror(UTF_ERR_SURROGATE, pos-2, surr)
                        invalids += 1
                    else
                        flags |= UTF_SURROGATE
                        num4byte += 1
                    end
                elseif ch > 0x07ff
                    num3byte += 1
                elseif accept_long_char
                    flags |= UTF_LONG
                    num2byte += 1
                elseif accept_invalids
                    invalids += 1
                else
                    unierror(UTF_ERR_LONG, pos-2, ch)
                end
            elseif ch < 0xf5
                # 4-byte UTF-8 sequence (i.e. characters > 0xffff)
                if pos + 2 > endpos
                    accept_invalids || unierror(UTF_ERR_SHORT, pos, ch)
                    invalids += 1
                    break
                end
                ch, pos, flg = check_continuation(dat, pos, ch & 0x07, accept_invalids)
                flg && (invalids += 1 ; continue)
                ch, pos, flg = check_continuation(dat, pos, ch, accept_invalids)
                flg && (invalids += 1 ; continue)
                ch, pos, flg = check_continuation(dat, pos, ch, accept_invalids)
                flg && (invalids += 1 ; continue)
                if ch > 0x10ffff
                    accept_invalids || unierror(UTF_ERR_INVALID, pos-3, ch)
                    invalids += 1
                elseif ch > 0xffff
                    num4byte += 1
                elseif is_surrogate_codeunit(ch)
                    accept_invalids || unierror(UTF_ERR_SURROGATE, pos-3, ch)
                    invalids += 1
                elseif accept_long_char
                    # This is an overly long encoded character
                    flags |= UTF_LONG
                    if ch > 0x7ff
                        num3byte += 1
                    elseif ch > 0x7f
                        num2byte += 1
                    end
                elseif accept_invalids
                    invalids += 1
                else
                    unierror(UTF_ERR_LONG, pos-2, ch)
                end
            elseif accept_invalids
                invalids += 1
            else
                unierror(UTF_ERR_INVALID, pos, ch)
            end
        end
    end
    _ret_check(totalchar, flags, invalids, latin1byte, num2byte, num3byte, num4byte)
end

function unsafe_check_string(dat::Union{AbstractVector{T}, Ptr{T}}, pos, endpos;
                             accept_long_null  = false,
                             accept_surrogates = false,
                             accept_long_char  = false,
                             accept_invalids   = false) where {T<:Union{UInt16,UInt32}}
    flags = 0%UInt
    totalchar = latin1byte = num2byte = num3byte = num4byte = invalids = 0
    @inbounds while pos <= endpos
        ch = get_codeunit(dat, pos)%UInt32
        pos += 1
        totalchar += 1
        if ch > 0x7f
            if ch < 0x100
                latin1byte += 1
            elseif ch < 0x800
                num2byte += 1
            elseif ch > 0x0ffff
                if (ch > 0x10ffff)
                    accept_invalids || unierror(UTF_ERR_INVALID, pos, ch)
                    invalids += 1
                else
                    num4byte += 1
                end
            elseif !is_surrogate_codeunit(ch)
                num3byte += 1
            elseif is_surrogate_lead(ch)
                if pos > endpos
                    accept_invalids || unierror(UTF_ERR_MISSING_SURROGATE, pos, ch)
                    invalids += 1
                    break
                end
                # next character *must* be a trailing surrogate character
                ch = get_codeunit(dat, pos)
                pos += 1
                if !is_surrogate_trail(ch)
                    accept_invalids || unierror(UTF_ERR_NOT_TRAIL, pos, ch)
                    invalids += 1
                elseif typeof(dat) <: AbstractVector{UInt16} # fix this test!
                    num4byte += 1
                elseif accept_surrogates
                    flags |= UTF_SURROGATE
                    num4byte += 1
                elseif accept_invalids
                    invalids += 1
                else
                    unierror(UTF_ERR_SURROGATE, pos, ch)
                end
            elseif accept_invalids
                invalids += 1
            else
                unierror(UTF_ERR_NOT_LEAD, pos, ch)
            end
        end
    end
    _ret_check(totalchar, flags, invalids, latin1byte, num2byte, num3byte, num4byte)
end

function unsafe_check_string(str::T;
                             accept_long_null  = false,
                             accept_surrogates = false,
                             accept_long_char  = false,
                             accept_invalids   = false) where {T<:AbstractString}
    flags = 0%UInt
    totalchar = latin1byte = num2byte = num3byte = num4byte = invalids = 0
    pos = start(str)
    @inbounds while !done(str, pos)
        chr, nxt = next(str, pos)
        ch = chr%UInt32
        totalchar += 1
        if ch > 0x7f
            if ch < 0x100
                latin1byte += 1
            elseif ch < 0x800
                num2byte += 1
            elseif ch > 0x0ffff
                if (ch > 0x10ffff)
                    accept_invalids || unierror(UTF_ERR_INVALID, pos, ch)
                    invalids += 1
                else
                    num4byte += 1
                end
            elseif !is_surrogate_codeunit(ch)
                num3byte += 1
            elseif is_surrogate_lead(ch)
                if done(str, nxt)
                    accept_invalids || unierror(UTF_ERR_MISSING_SURROGATE, pos, ch)
                    invalids += 1
                    break
                end
                # next character *must* be a trailing surrogate character
                chr, nxt = next(str, nxt)
                if !is_surrogate_trail(chr)
                    accept_invalids || unierror(UTF_ERR_NOT_TRAIL, pos, chr)
                    invalids += 1
                elseif accept_surrogates
                    flags |= UTF_SURROGATE
                    num4byte += 1
                elseif accept_invalids
                    invalids += 1
                else
                    unierror(UTF_ERR_SURROGATE, pos, ch)
                end
            elseif accept_invalids
                invalids += 1
            else
                unierror(UTF_ERR_NOT_LEAD, pos, ch)
            end
        end
        pos = nxt
    end
    _ret_check(totalchar, flags, invalids, latin1byte, num2byte, num3byte, num4byte)
end

@inline function skipascii(beg::Ptr{UInt8}, fin::Ptr{UInt8})
    align = reinterpret(UInt, beg)
    pnt = reinterpret(Ptr{UInt64}, align & ~CHUNKMSK)
    v = unsafe_load(pnt)
    (align &= CHUNKMSK) != 0 && (v &= ~_mask_bytes(align))
    while (pnt += CHUNKSZ) < fin
        # find first byte that is not ASCII
        (v &= hi_mask) == 0 || return Int(pnt - CHUNKSZ - beg + (trailing_zeros(v)>>>3))
        v = unsafe_load(pnt)
    end
    Int(pnt - CHUNKSZ - beg +
        (trailing_zeros((pnt == fin ? v : (v | ~_mask_bytes(fin - pnt - CHUNKSZ))) & hi_mask)>>>3))
end

function fast_check_string(beg::Ptr{UInt8}, len)
    pnt = beg
    fin = pnt + len
    flags = 0%UInt
    asciichar = latin1byte = num2byte = num3byte = num4byte = 0
    while pnt < fin
        ch = get_codeunit(pnt)
        if ch < 0x80
            cnt = skipascii(pnt, fin)
            asciichar += cnt
            pnt += cnt
            continue
        # Check UTF-8 encoding
        elseif ch < 0xe0
            # 2-byte UTF-8 sequence (i.e. characters 0x80-0x7ff)
            (pnt += 1) < fin || unierror(UTF_ERR_SHORT, pnt - beg, ch)
            (ch > 0xc1 && checkcont(pnt)) || unierror(UTF_ERR_INVALID, pnt - beg, ch)
            ch > 0xc3 ? (num2byte += 1) : (latin1byte += 1)
        elseif ch < 0xf0
            # 3-byte UTF-8 sequence (i.e. characters 0x800-0xffff)
            (pnt += 2) < fin || unierror(UTF_ERR_SHORT, pnt - beg - 1, ch)
            b2 = get_codeunit(pnt - 1)
            (is_valid_continuation(b2) && checkcont(pnt)) ||
                unierror(UTF_ERR_INVALID, pnt - beg - 1, ch)
            if ch == 0xe0 # Might be overlong
                b2 < 0xa0 && unierror(UTF_ERR_LONG, pnt - beg - 1, get_utf8_3byte(pnt, ch))
            elseif ch == 0xed # Might be surrogate pair
                b2 > 0x9f && unierror(UTF_ERR_SURROGATE, pnt - beg - 1, get_utf8_3byte(pnt, ch))
            end
            num3byte += 1
        elseif ch < 0xf5
            # 4-byte UTF-8 sequence (i.e. characters > 0xffff)
            (pnt += 3) < fin || unierror(UTF_ERR_SHORT, pnt - beg - 2, ch)
            b2 = get_codeunit(pnt - 2)
            #println(ch,", ",b2,", ",get_codeunit(pnt-1),", ",get_codeunit(pnt))
            (is_valid_continuation(b2) && checkcont(pnt-1) && checkcont(pnt)) ||
                unierror(UTF_ERR_INVALID, pnt - beg - 2, ch)
            if ch == 0xf0
                b2 < 0x90 && unierror(UTF_ERR_LONG, pnt - beg - 2, get_utf8_4byte(pnt, ch))
            elseif ch == 0xf4
                b2 > 0x8f && unierror(UTF_ERR_INVALID, pnt - beg - 2, get_utf8_4byte(pnt, ch))
            end
            num4byte += 1
        else
            unierror(UTF_ERR_INVALID, pnt - beg + 1, ch)
        end
        pnt += 1
    end
    _ret_check(asciichar+latin1byte+num2byte+num3byte+num4byte,
               flags, 0, latin1byte, num2byte, num3byte, num4byte)
end

const _bmp_mask = 0xd800_d800_d800_d800
@inline _mask_allsurr(v)  = xor((v | v<<1 | v<<2 | v<<3 | v<<4) & _hi_bit_16, _hi_bit_16)

@inline _get_bmp_mask(v::UInt64) = _mask_allsurr(xor(v, _bmp_mask))

const msk_ascii_16 = 0xff80ff80ff80ff80
const msk_latin_16 = 0xff00ff00ff00ff00
const msk_num2b_16 = 0xf800f800f800f800

# v -> 1111 1yyy l000 0000 1111 1yyy l000 0000 1111 1yyy l000 0000 1111 1yyy l000 0000

@inline function countmask(v, cnta, cntl, cnt2, cnt3)
    # First mask off ASCII bits: 0xff80ff80ff80ff80, count all 0 words (0-4)
    # Then mask off Latin1 bits: 0xff00ff00ff00ff00, count all 0 words (0-4)
    # Then mask off num2byte:    0xf800f800f800f800, count all 0 words (0-4)
    va = v & msk_ascii_16
    vl = v & msk_latin_16
    v2 = v & msk_num2b_16
    println("v=$v, 0x$(hex(va)), 0x$(hex(vl)), 0x$(hex(v2)), $cnta, $cntl, $cnt2, $cnt3")
    cnta, cntl, cnt2, cnt3
end

@inline function skipbmp(beg::Ptr{UInt16}, fin, cnta, cntl, cnt2, cnt3)
    align = reinterpret(UInt, beg)
    pnt = reinterpret(Ptr{UInt64}, align & ~CHUNKMSK)
    v = unsafe_load(pnt)
    (align &= CHUNKMSK) != 0 && (v &= ~_mask_bytes(align))
    while (pnt += CHUNKSZ) < fin
        # If vm is 0, it means there are non-BMP characters present
        if (vm = _get_bmp_mask(v)) == 0
            # Get how many characters are before the non-BMP character
            cnt = (leading_zeros(vm)>>>3)&~1
            v &= _mask_bytes(cnt)
            return pnt - CHUNKSZ + cnt, countmask(v, cnta, cntl, cnt2, cnt3)...
        end
        cnta, cntl, cnt2, cnt3 = countmask(v, cnta, cntl, cnt2, cnt3)
        v = unsafe_load(pnt)
    end
    v = (pnt == fin ? v : (v & _mask_bytes(fin - pnt - CHUNKSZ)))
    if (vm = _get_bmp_mask(v)) == 0
        # Get how many characters are before the non-BMP character
        cnt = (leading_zeros(vm)>>>3)&~1
        v &= _mask_bytes(cnt)
        fin = pnt - CHUNKSZ + cnt
    end
    fin, countmask(v, cnta, cntl, cnt2, cnt3)...
end

# Check for valid UTF-16
function fast_check_string(beg::Ptr{UInt16}, len)
    pnt = beg
    fin = bytoff(pnt, len)
    flags = 0%UInt
    asciichar = latin1byte = num2byte = num3byte = num4byte = 0
    while pnt < fin
        ch = get_codeunit(pnt)
        #=
        if !is_surrogate_codepoint(ch)
            pnt, asciichar, latin1byte, num2byte, num3byte =
                skipbmp(pnt, fin, asciichar, latin1byte, num2byte, num3byte)
        =#
        if ch <= 0x7f
            asciichar += 1
        elseif ch <= 0xff
            latin1byte += 1
        elseif ch < 0x7ff
            num2byte += 1
        elseif !is_surrogate_codeunit(ch)
            num3byte += 1
        elseif !is_surrogate_lead(ch)
            unierror(UTF_ERR_NOT_LEAD, Int((pnt - beg)>>>1), ch)
        elseif (pnt += 2) >= fin
            unierror(UTF_ERR_SHORT, Int((pnt - beg - 2)>>>1), ch)
        else
            c2 = get_codeunit(pnt)
            is_surrogate_trail(c2) || unierror(UTF_ERR_NOT_TRAIL, Int((pnt - beg)>>>1), c2)
            pnt += 2
            num4byte += 1
        end
        pnt += 2
    end
    _ret_check(asciichar+latin1byte+num2byte+num3byte+num4byte,
               flags, 0, latin1byte, num2byte, num3byte, num4byte)
end

# Check for valid UTF-32
function fast_check_string(beg::Ptr{UInt32}, len)
    pnt = beg
    fin = bytoff(pnt, len)
    flags = 0%UInt
    asciichar = latin1byte = num2byte = num3byte = num4byte = 0
    while pnt < fin
        ch = get_codeunit(pnt)
        if ch <= 0x7f
            asciichar += 1
        elseif ch <= 0xff
            latin1byte += 1
        elseif ch <= 0x7ff
            num2byte += 1
        elseif ch <= 0xd7ff
            num3byte += 1
        elseif ch <= 0xdfff
            unierror(UTF_ERR_SURROGATE, (pnt-beg+4)>>>2, ch)
        elseif ch <= 0xffff
            num3byte += 1
        elseif ch <= 0x10ffff
            num4byte += 1
        else
            unierror(UTF_ERR_INVALID, (pnt-beg+4)>>>2, ch)
        end
        pnt += 4
    end
    _ret_check(asciichar+latin1byte+num2byte+num3byte+num4byte,
               flags, 0, latin1byte, num2byte, num3byte, num4byte)
end

"""
Calculate the total number of characters, as well as number of
latin1, 2-byte, 3-byte, and 4-byte sequences in a validated UTF-8 string
"""
function count_chars(::Type{UTF8Str}, ::Type{S}, dat::Union{AbstractVector{S}, Ptr{S}},
                     pos, len) where {S<:CodeUnitTypes}
    totalchar = latin1byte = num2byte = num3byte = num4byte = 0
    @inbounds while pos <= len
        ch = get_codeunit(dat, pos)
        totalchar += 1
        if ch < 0x80 # ASCII characters
            pos += 1
        elseif ch < 0xc4 # 2-byte Latin 1 characters (0x80-0xff)
            latin1byte += 1
            pos += 2
        elseif ch < 0xe0 # 2-byte BMP sequence (i.e. characters 0x100-0x7ff)
            pos += 2
            num2byte += 1
        elseif ch < 0xf0 # 3-byte BMP sequence (0x800-0xffff)
            pos += 3
            num3byte += 1
        else # 4-byte non-BMP sequence (0x10000 - 0x10ffff)
            pos += 4
            num4byte += 1
        end
    end
    _ret_check(totalchar, 0%UInt, 0, latin1byte, num2byte, num3byte, num4byte)
end

"""
Calculate the total number of characters, as well as number of
latin1, 2-byte, 3-byte, and 4-byte sequences in a validated UTF-16, UCS2, or UTF-32 string
"""
function count_chars(::Type{T}, ::Type{S}, dat::Union{AbstractVector{S}, Ptr{S}},
                     pos, endpos) where {S<:CodeUnitTypes, T<:Str}
    totalchar = latin1byte = num2byte = num3byte = num4byte = 0
    @inbounds while pos <= endpos
        ch = get_codeunit(dat, pos)%UInt32
        pos += 1
        totalchar += 1
        if ch <= 0x7f # ASCII characters
        elseif ch <= 0xff # 2-byte Latin 1 characters (0x80-0xff)
            latin1byte += 1
        elseif ch <= 0x7ff # 2-byte BMP sequence (i.e. characters 0x100-0x7ff)
            num2byte += 1
        elseif T == UTF16Str
            if is_surrogate_lead(ch)
                pos += 1
                num4byte += 1
            else
                num3byte += 1
            end
        elseif ch <= 0xffff # 3-byte BMP sequence (0x800-0xffff)
            num3byte += 1
        else # 4-byte non-BMP sequence (0x10000 - 0x10ffff)
            num4byte += 1
        end
    end
    _ret_check(totalchar, 0%UInt, 0, latin1byte, num2byte, num3byte, num4byte)
end

count_chars(T, dat, len) = count_chars(T, codeunit(T), dat, 1, len)

"""
Calculate the total number of bytes > 0x7f
"""
function count_latin(len, pnt::Ptr{UInt8})
    # Todo: optimize this to work on chunks when pnt is aligned
    cnt = 0
    fin = pnt + len
    while pnt < fin
        cnt += (get_codeunit(pnt) > 0x7f)
        pnt += 1
    end
    cnt
end

"""
Validates and calculates number of characters in a UTF-8,UTF-16 or UTF-32 encoded vector/string

This function checks the bounds of the start and end positions
Use `unsafe_check_string` to avoid that overhead if the bounds have already been checked

Input Arguments:

* `dat`    UTF-8 (`Vector{UInt8}`), UTF-16 (`Vector{UInt16}`) or UTF-32 (`Vector{UInt32}`, `AbstractString`) encoded string

Optional Input Arguments:

* `startpos` start position (defaults to 1)
* `endpos`   end position   (defaults to `lastindex(dat)`)

Keyword Arguments:

* `accept_long_null`  = `false`  # Modified UTF-8 (`\\0` represented as `b\"\\xc0\\x80\"`)
* `accept_surrogates` = `false`  # `CESU-8`
* `accept_long_char`  = `false`  # Accept arbitrary long encodings
* `accept_invalids`   = `false`  # Accept invalid sequences (to be replaced on conversion)

Returns:

* (total characters, flags, 4-byte, 3-byte, 2-byte)

Throws:

* `UnicodeError`
"""
function check_string end

# No need to check bounds if using defaults
check_string(dat; kwargs...) = unsafe_check_string(dat, 1, lastindex(dat); kwargs...)

# Make sure that beginning and end positions are bounds checked
function check_string(dat, startpos, endpos = lastindex(dat); kwargs...)
    @boundscheck checkbounds(dat, startpos)
    @boundscheck checkbounds(dat, endpos)
    endpos < startpos && argerror(startpos, endpos)
    unsafe_check_string(dat, startpos, endpos; kwargs...)
end

byte_string_classify(data) =
    ccall(:u8_isvalid, Int32, (Ptr{UInt8}, Int), data, length(data))
byte_string_classify(data::Vector{UInt8}) =
    ccall(:u8_isvalid, Int32, (Ptr{UInt8}, Int), data, length(data))
byte_string_classify(s::Str{<:Byte_CSEs}) = byte_string_classify(s.data)
    # 0: neither valid ASCII nor UTF-8
    # 1: valid ASCII
    # 2: valid UTF-8

is_valid(::Type{ASCIIStr},  s::Vector{UInt8}) = is_ascii(s)
is_valid(::Type{UTF8Str},   s::Vector{UInt8}) = byte_string_classify(s) != 0
is_valid(::Type{<:Str{LatinCSE}},  s::Vector{UInt8}) = true
# This should be optimized, stop at first character > 0x7f
is_valid(::Type{<:Str{_LatinCSE}}, s::Vector{UInt8}) = !is_ascii(s)

is_valid(::Type{UniStr}, s::String) = is_unicode(s)
is_valid(::Type{<:Str{C}}, s::String) where {C<:Union{UTF8CSE,UTF16CSE,UTF32CSE}} = is_unicode(s)
is_valid(::Type{<:Str{ASCIICSE}}, s::String) = is_ascii(s)
is_valid(::Type{<:Str{UCS2CSE}}, s::String)  = is_bmp(s)
is_valid(::Type{<:Str{LatinCSE}}, s::String) = is_latin(s)

function _copysub(pnt::Ptr{T}, len) where {T<:CodeUnitTypes}
    buf, out = _allocate(eltype(pnt), len)
    _memcpy(out, pnt, len)
    buf
end
_copysub(str::String)    = str
_copysub(str::Str)       = str.data
_copysub(str::SubString) = @preserve str _copysub(pointer(str), ncodeunits(str))
_copysub(vec::Vector)    = @preserve vec _copysub(pointer(vec), length(vec))

function _cvtsize(::Type{T}, dat, len) where {T <: CodeUnitTypes}
    buf, pnt = _allocate(T, len)
    @inbounds for i = 1:len
        set_codeunit!(pnt, get_codeunit(dat, i))
        pnt += sizeof(T)
    end
    buf
end

function _cvtsize(::Type{T}, pnt::Ptr{S}, len) where {S<:CodeUnitTypes,T<:CodeUnitTypes}
    buf, out = _allocate(T, len)
    fin = bytoff(pnt, len)
    #println("buf=$buf, out=$out, pnt=$pnt, fin=$fin, len=$len")
    while pnt < fin
        set_codeunit!(out, get_codeunit(pnt))
        out += sizeof(T)
        pnt += sizeof(S)
    end
    buf
end

(*)(s1::Union{C1, S1}, ss::Union{C2, S2}...) where {C1<:Chr,C2<:Chr,S1<:Str,S2<:Str} =
    string(s1, ss...)

thisind(str::MaybeSub{<:Str}, i::Integer) = thisind(str, Int(i))

function filter(fun, str::MaybeSub{T}) where {C<:CSE,T<:Str{C}}
    out = get_iobuffer(sizeof(str))
    @inbounds for ch in codepoints(str)
        fun(ch) && _write(C, out, ch)
    end
    Str{C}(String(take!(out)))
end

# Todo: These should be optimized based on the traits, and return internal substrings, once
# I've implemented those

first(str::Str, n::Integer) = str[1:min(end, nextind(str, 0, n))]
last(str::Str, n::Integer)  = str[max(1, prevind(str, ncodeunits(str)+1, n)):end]

const Chrs = @static V6_COMPAT ? Union{Char,AbstractChar} : Chr

function repeat(ch::CP, cnt::Integer) where {CP <: Chrs}
    C = codepoint_cse(CP)
    cnt > 1 && return Str(C, _repeat(CodePointStyle(C), C, codepoint(ch), cnt))
    cnt < 0 && repeaterr(cnt)
    cnt == 0 ? empty_str(C) : _convert(C, codepoint(ch))
end

(^)(ch::CP, cnt::Integer) where {CP <: Chrs} = repeat(ch, cnt)

# low level mem support functions

const (WidChr,OthChr) = @static sizeof(Cwchar_t) == 4 ? (UInt32,UInt16) : (UInt16,UInt32)

_fwd_memchr(ptr::Ptr{UInt8}, byt::UInt8, len::Integer) =
    ccall(:memchr, Ptr{UInt8}, (Ptr{UInt8}, Int32, Csize_t), ptr, byt, len)

_fwd_memchr(ptr::Ptr{WidChr}, wchr::WidChr, len::Integer) =
    ccall(:wmemchr, Ptr{WidChr}, (Ptr{WidChr}, Int32, Csize_t), ptr, wchr, len)

_fwd_memchr(beg::Ptr{OthChr}, wchr::OthChr, len::Integer) =
    _fwd_memchr(beg, ch, bytoff(beg, len))

_fwd_memchr(ptr::Ptr{UInt8}, byt::UInt8, fin::Ptr{UInt8}) =
    ptr < fin ? _fwd_memchr(ptr, byt, fin - ptr) : C_NULL

_fwd_memchr(ptr::Ptr{WidChr}, wchr::WidChr, fin::Ptr{WidChr}) =
    ptr < fin ? _fwd_memchr(ptr, wchr, chroff(fin - ptr)) : C_NULL

function _fwd_memchr(pnt::Ptr{T}, wchr::T, fin::Ptr{T}) where {T<:OthChr}
    while pnt < fin
        get_codeunit(pnt) == ch && return pnt
        pnt += sizeof(T)
    end
    C_NULL
end

_rev_memchr(ptr::Ptr{UInt8}, byt::UInt8, len::Integer) =
    ccall(:memrchr, Ptr{UInt8}, (Ptr{UInt8}, Int32, Csize_t), ptr, byt, len)

function _rev_memchr(beg::Ptr{T}, ch::T, len::Integer) where {T<:Union{UInt16,UInt32}}
    pnt = bytoff(beg, len)
    while (pnt -= sizeof(T)) >= beg
        get_codeunit(pnt) == ch && return pnt
    end
    C_NULL
end

_memcmp(a::Ptr{UInt8}, b::Ptr{UInt8}, len) =
    ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt), a, b, len)
_memcmp(a::Ptr{WidChr}, b::Ptr{WidChr}, len) =
    ccall(:wmemcmp, Int32, (Ptr{WidChr}, Ptr{WidChr}, UInt), a, b, len)

function _memcmp(apnt::Ptr{OthChr}, bpnt::Ptr{OthChr}, len)
    fin = bytoff(apnt, len)
    while apnt < fin
        (c1 = get_codeunit(apnt)) == (c2 = get_codeunit(bpnt)) || return _cmp(c1, c2)
        apnt += sizeof(OthChr)
        bpnt += sizeof(OthChr)
    end
    0
end

# These should probably be handled by traits, or dispatched by getting the codeunit type for each
_memcmp(a::Union{String, Str{<:Byte_CSEs}},
        b::Union{String, Str{<:Byte_CSEs}, SubString{String}, SubString{<:Str{<:Byte_CSEs}}}, siz) =
    _memcmp(pointer(a), pointer(b), siz)
_memcmp(a::SubString{<:Union{String, Str{<:Byte_CSEs}}}, b::Union{String, Str{<:Byte_CSEs}}, siz) =
    _memcmp(pointer(a), pointer(b), siz)
_memcmp(a::SubString{<:Union{String, Str{<:Byte_CSEs}}},
        b::SubString{<:Union{String, Str{<:Byte_CSEs}}}, siz) =
    _memcmp(pointer(a), pointer(b), siz)

_memcmp(a::Str{<:Word_CSEs}, b::MaybeSub{<:Str{<:Word_CSEs}}, siz) =
    _memcmp(pointer(a), pointer(b), siz)
_memcmp(a::Str{<:Quad_CSEs}, b::MaybeSub{<:Str{<:Quad_CSEs}}, siz) =
    _memcmp(pointer(a), pointer(b), siz)
_memcmp(a::SubString{<:Str{<:Word_CSEs}}, b::Str{<:Word_CSEs}, siz) =
    _memcmp(pointer(a), pointer(b), siz)
_memcmp(a::SubString{<:Str{<:Quad_CSEs}}, b::Str{<:Quad_CSEs}, siz) =
    _memcmp(pointer(a), pointer(b), siz)
_memcmp(a::SubString{<:Str{<:Word_CSEs}}, b::SubString{<:Str{Word_CSEs}}, siz) =
    _memcmp(pointer(a), pointer(b), siz)
_memcmp(a::SubString{<:Str{<:Quad_CSEs}}, b::SubString{<:Str{Quad_CSEs}}, siz) =
    _memcmp(pointer(a), pointer(b), siz)

_memcpy(dst::Ptr{UInt8}, src::Ptr, siz) =
    ccall(:memcpy, Ptr{UInt8}, (Ptr{Cvoid}, Ptr{Cvoid}, UInt), dst, src, siz)
_memcpy(a::Ptr{WidChr}, b::Ptr{WidChr}, len) =
    ccall(:wmemcpy, Ptr{WidChr}, (Ptr{WidChr}, Ptr{WidChr}, UInt), a, b, len)
_memcpy(a::Ptr{OthChr}, b::Ptr{OthChr}, len) =
    ccall(:memcpy, Ptr{OthChr}, (Ptr{OthChr}, Ptr{OthChr}, UInt), a, b, bytoff(OthChr, len))

@inline _memset(pnt::Ptr{UInt8}, ch::UInt8, cnt) =
    ccall(:memset, Ptr{UInt8}, (Ptr{UInt8}, Cint, Csize_t), pnt, ch, cnt)
@inline _memset(pnt::Ptr{WidChr}, ch::WidChr, cnt) =
    ccall(:wmemset, Ptr{WidChr}, (Ptr{WidChr}, Cuint, Csize_t), pnt, ch, cnt)

@inline function _memset(pnt::Ptr{OthChr}, ch::OthChr, cnt)
    fin = bytoff(pnt, cnt)
    while pnt < fin
        set_codeunit!(pnt, ch)
        pnt += sizeof(OthChr)
    end
end

# Little-endian output here
@inline get_utf8_16(ch) =
    (ch >>> 6) | ((ch & 0x3f)%UInt16<<8) | 0x80c0
@inline get_utf8_32(ch) =
    (ch & 0xc0000 >>> 18) | (ch & 0x3f000 >>> 4) |
    (ch & 0xfc0 << 10) | (ch & 0x3f)<<24 | 0x808080f0
@inline get_utf16_32(ch) =
    (0xd7c0 + (ch >>> 10))%UInt16 << 6 | (0xdc00 + (ch & 0x3ff))%UInt32

@inline function _repeat_chr(::Type{T}, ch, cnt) where {T<:CodeUnitTypes}
    #println("_repeat_chr($T, $ch, $cnt)")
    buf, pnt = _allocate(T, cnt)
    _memset(pnt, ch%T, cnt)
    buf
end

@inline function _repeat_3(ch, cnt)
    buf, pnt = _allocate(UInt8, cnt*3)
    b1, b2, b3 = get_utf8_3(ch)
    fin = pnt + cnt*3
    while pnt < fin
        set_codeunit!(pnt,     b1)
        set_codeunit!(pnt + 1, b2)
        set_codeunit!(pnt + 2, b3)
        pnt += 3
    end
    buf
end

_repeat(::CodeUnitSingle, ::Type{C}, ch::T, cnt) where {T,C<:CSE} =
    _repeat_chr(basetype(T), ch, cnt)

function _repeat(::CodeUnitMulti, ::Type{UTF8CSE}, ch, cnt)
    if ch <= 0x7f
        _repeat_chr(UInt8, ch, cnt)
    elseif ch <= 0x7ff
        _repeat_chr(UInt16, get_utf8_16(ch), cnt)
    elseif ch <= 0xffff
        _repeat_3(ch, cnt)
    else
        _repeat_chr(UInt32, get_utf8_32(ch), cnt)
    end
end

_repeat(::CodeUnitMulti, ::Type{UTF16CSE}, ch, cnt) =
    ch <= 0xffff ? _repeat_chr(UInt16, ch, cnt) : _repeat_chr(UInt32, get_utf16_32(ch), cnt)

function repeat(str::T, cnt::Integer) where {C<:CSE,T<:Str{C}}
    cnt < 2 && return cnt == 1 ? str : (cnt == 0 ? empty_str(C) : repeaterr(cnt))
    CU = codeunit(T)
    @preserve str begin
        len = ncodeunits(str)
        totlen = len * cnt
        buf, out = _allocate(CU, totlen)
        if len == 1 # common case: repeating a single codeunit string
            _memset(out, get_codeunit(pointer(str)), cnt)
        else
            pnt = pointer(str)
            fin = bytoff(out, totlen)
            siz = bytoff(CU, len)
            while out < fin
                _memcpy(out, pnt, len)
                out += siz
            end
        end
    end
    Str(C, buf)
end
(^)(str::T, cnt::Integer) where {T<:Str} = repeat(str, cnt)

# Definitions for C compatible strings, that don't allow embedded
# '\0', and which are terminated by a '\0'

containsnul(str::Str{<:Byte_CSEs}) = containsnul(unsafe_convert(Ptr{Cchar}, str), sizeof(str))

# Check 4 characters at a time
function containsnul(str::Str{<:Word_CSEs})
    (siz = sizeof(str)) == 0 && return true
    @preserve str begin
        pnt, fin = _calcpnt(str, siz)
        while (pnt += CHUNKSZ) <= fin
            ((v = unsafe_load(pnt))%UInt16 == 0 || (v>>>16)%UInt16 == 0 ||
             (v>>>32)%UInt16 == 0 || (v>>>48) == 0) && return true
        end
        pnt - CHUNKSZ != fin &&
            ((v = (unsafe_load(pnt) | ~_mask_bytes(siz)))%UInt16 == 0 ||
             (v>>>16)%UInt16 == 0 || (v>>>32)%UInt16 == 0)
    end
end

function containsnul(str::Str{<:Quad_CSEs})
    (siz = sizeof(str)) == 0 && return true
    @preserve str begin
        pnt, fin = _calcpnt(str, siz)
        while (pnt += CHUNKSZ) <= fin
            ((v = unsafe_load(pnt))%UInt32 == 0 || (v>>>32) == 0) && return true
        end
        pnt - CHUNKSZ != fin && unsafe_load(reinterpret(Ptr{UInt32}, pnt)) == 0x00000
    end
end
