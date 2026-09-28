//! Text tables for the US dialogue, generated from the old assets/text_compression.py.
//!
//! The alphabet maps a byte to the characters it prints - most entries are a
//! single character, but a few are bracketed names for glyphs that have no
//! ASCII spelling. The dictionary is matched in this exact order when
//! compressing, first match winning rather than longest, so the order is part
//! of the format.

pub const kAlphabet = [_][]const u8{
    "A",         "B",         "C",         "D",         "E",         "F",
    "G",         "H",         "I",         "J",         "K",         "L",
    "M",         "N",         "O",         "P",         "Q",         "R",
    "S",         "T",         "U",         "V",         "W",         "X",
    "Y",         "Z",         "a",         "b",         "c",         "d",
    "e",         "f",         "g",         "h",         "i",         "j",
    "k",         "l",         "m",         "n",         "o",         "p",
    "q",         "r",         "s",         "t",         "u",         "v",
    "w",         "x",         "y",         "z",         "0",         "1",
    "2",         "3",         "4",         "5",         "6",         "7",
    "8",         "9",         "!",         "?",         "-",         ".",
    ",",         "[...]",     ">",         "(",         ")",         "[Ankh]",
    "[Waves]",   "[Snake]",   "[LinkL]",   "[LinkR]",   "\"",        "[Up]",
    "[Down]",    "[Left]",    "[Right]",   "'",         "[1HeartL]", "[1HeartR]",
    "[2HeartL]", "[3HeartL]", "[3HeartR]", "[4HeartL]", "[4HeartR]", " ",
    "<",         "[A]",       "[B]",       "[X]",       "[Y]",
};

pub const kDictionary = [_][]const u8{
    "    ", "   ",  "  ",    "'s ",
    "and ", "are ", "all ",  "ain",
    "and",  "at ",  "ast",   "an",
    "at",   "ble",  "ba",    "be",
    "bo",   "can ", "che",   "com",
    "ck",   "des",  "di",    "do",
    "en ",  "er ",  "ear",   "ent",
    "ed ",  "en",   "er",    "ev",
    "for",  "fro",  "give ", "get",
    "go",   "have", "has",   "her",
    "hi",   "ha",   "ight ", "ing ",
    "in",   "is",   "it",    "just",
    "know", "ly ",  "la",    "lo",
    "man",  "ma",   "me",    "mu",
    "n't ", "non",  "not",   "open",
    "ound", "out ", "of",    "on",
    "or",   "per",  "ple",   "pow",
    "pro",  "re ",  "re",    "some",
    "se",   "sh",   "so",    "st",
    "ter ", "thin", "ter",   "tha",
    "the",  "thi",  "to",    "tr",
    "up",   "ver",  "with",  "wa",
    "we",   "wh",   "wi",    "you",
    "Her",  "Tha",  "The",   "Thi",
    "You",
};

pub const kCommandNames = [_][]const u8{
    "NextPic",     "Choose",       "Item",         "Name",
    "Window",      "Number",       "Position",     "ScrollSpd",
    "Selchg",      "Unused_Crash", "Choose3",      "Choose2",
    "Scroll",      "1",            "2",            "3",
    "Color",       "Wait",         "Sound",        "Speed",
    "Unused_Mark", "Unused_Mark2", "Unused_Clear", "Waitkey",
};

pub const kCommandLengths = [_]u8{ 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 1 };
