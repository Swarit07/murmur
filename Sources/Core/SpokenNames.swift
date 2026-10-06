import Foundation

/// How hard-to-spell names are said, for names the user has put in their dictionary (`SpellingMatcher`).
/// The engine writes what it hears ("Chivan"), which no spelling rule connects to "Siobhan"; matching the
/// heard word's sound against the spoken form does. Only names whose sound key is long enough to be safe are
/// listed (at least three consonant sounds), and a spoken form is only used when that name is in the dictionary.
/// Names that sound like a common name are left out (Clodagh ~ Claude, Caoilfhionn ~ Colin, Aoibheann ~ Evan,
/// Ciarán ~ Karen, Gruffydd ~ Griffith, Gráinne ~ Greene, Mairéad ~ Murad), so a different person's name is not
/// rewritten; the matcher also wants the heard word spelled close to the spoken form, not only sounding like it.
public enum SpokenNames {
    /// Folded spelling key (`SpellingMatcher.key`) to spoken forms, written as they sound.
    public static let forms: [String: [String]] = [
        // Irish
        "siobhan": ["shivawn", "shivon"],
        "saoirse": ["seersha", "sersha"],
        "sinead": ["shinade", "shinaid"],
        "oisin": ["osheen", "usheen"],
        "roisin": ["rosheen"],
        "padraig": ["pawdrig", "podrig"],
        "deirdre": ["deerdra"],
        "aisling": ["ashling", "ashlin"],
        "dearbhla": ["dervla"],
        "seamus": ["shaymus"],
        // Welsh
        "dafydd": ["davith"],
        // Spanish
        "joaquin": ["wakeen", "hwakeen"],
        "xiomara": ["seeomara"],
        "guillermo": ["geeyermo"],
    ]
}
