import Foundation

/// Apollo's end-of-feed cell: a message and, from the second visit on, a
/// large beast who talks to you. Strings are verbatim from Apollo.
///
/// The cell carries three background dinosaur illustrations. Apollo's
/// own artwork is not reproduced here; `ReachedEndView` draws the
/// message and leaves the illustration out rather than shipping it.
public enum ReachedEndCopy {
    /// Key `EndsOfRedditsReached3`, an integer visit counter in
    /// `NSUserDefaults`, incremented on init. The same counter selects the
    /// dialogue below.
    public static let visitCountKey = "EndsOfRedditsReached3"

    /// Shown when Apollo does NOT believe you have hit the end of
    /// everything loadable, i.e. the feed merely stopped.
    public static let shortHeadline = "The Great Scrolls of Reddit claim you\u{2019}ve reached the end of this feed."

    /// The variant shown when it does, which suggests what to do next.
    public static let longHeadline = "The Great Scrolls of Reddit claim there\u{2019}s no more content past this point. Try loading a new subreddit, or if it\u{2019}s been a bit, refreshing this one."

    /// Bridges the headline into the beast's line. Note the leading
    /// newlines and opening curly quote: the beast's dialogue is
    /// quoted speech.
    public static let beastIntro = "\n\nSuddenly, the ground shakes, and a large beast emerges, saying:\n\n\u{201C}"

    /// The closing curly quote appended after the dialogue line.
    public static let beastOutro = "\u{201D}"

    /// The beast's FIRST-visit line, used when the counter reads
    /// exactly 1.
    public static let firstVisitLine = "Not many people visit me all the way down here. It\u{2019}s great to meet another soul."

    /// The cell's accessibility label.
    public static let accessibilityLabel = "Wow. You reached the bottom."

    /// Accessibility hint.
    public static let accessibilityHint = "Double tap to communicate to Chumbus"

    /// The beast's other 50 lines, verbatim and in order.
    ///
    /// Selection: read `EndsOfRedditsReached3`; if it is 1 use
    /// `firstVisitLine`; otherwise index this table at `count - 2`,
    /// and once that runs past the end pick a RANDOM element instead.
    /// So the lines are seen in order on your first 51 visits and
    /// shuffle forever after.
    public static let beastLines: [String] = [
        "You again, huh? Are you making a habit of visiting me?",
        "I appreciate you taking the time to stop by and say hello.",
        "HUH, WHAT— Oh. Righteo. Sorry, I was sleeping and you startled me.",
        "If you're going to stay awhile, do you mind taking off your shoes?",
        "Sometimes, I wrap myself in large velvety curtains and dance to the Beauty and the Beast soundtrack. (I am the beast.)",
        "The dirt down here is just the most beautiful shade of brown today.",
        "There are other ways to encounter me other than traveling so deep, but this is arguably the friendliest.",
        "If it’s still in season when you return next, could you grab me a McLobster?",
        "Sometimes, a kitten strolls by these parts looking for a mouse, and briefly stops to purr and let me pet.",
        "Hello again! Look what this penguin gave me the other day! *holds up spork*",
        "Often times I’ll be sleeping and a big clod of dirt falls down here and boops me in the snoot.",
        "Sometimes when I need to get around down here, an enormous stag beetle helps me travel about.",
        "The other day I came across some ancient hieroglyphics of a peach emoji.",
        "You look slightly parched. Are you drinking enough water?",
        "The only movie we get down here is a strange movie with a goat protagonist from the Czech Republic.",
        "You’ll never believe, a young man came by the other day looking for his mother Persephone. Alas, I was of no help.",
        "One time, I went to meet my old partner’s parents, and I pretended not to know what a potato was. We are no longer together.",
        "My diet consists solely of app icons. Why else would this app have so many?",
        "The only other person I can remember meeting down here was this kid named Kevin who ate an entire pack of crayons.",
        "Have you heard of someone who goes by “Ebony Dark’ness Dementia Raven Way”? Eyes like limpid tears?",
        "Oh, you again! How are things, anything changed since we last talked?",
        "It’s hard to keep plants alive down here where it’s so dark, so I mostly keep fake plants.",
        "Lately I’ve been trying to get into this thing called “hydroponics”.",
        "You came all the way down here and still can connect to the internet? Share your secrets!",
        "A few more visits and I’ll consider sharing with you my cherry cheesecake recipe. ",
        "My favorite food to complement the dank environment down here is a lasagna made with fresh tomatoes.",
        "Down here, the pressure is much higher than at sea level, so there’s some very weird fish.",
        "Are you telling me I live inside an electronic device? As if I’d believe that.",
        "At these depths the pressure exerted by the earth’s crust is immense. ",
        "Back when I briefly lived on the surface, I knew a guy with a Pro Display XDR.",
        "Sometimes quite a bit of time passes between your visits. Do you have any podcast recommendations? Oh, you’re thinking of starting your own? Never mind.",
        "Down here I’m often left alone with my thoughts, so I write fanfics about my favorite video games. I’m too shy to share, though.",
        "I bet your travels down this deep are influenced by the hit 2003 film “Holes”. I have it on VHS if you want to watch.",
        "Ah ha, it’s been awhile! You don’t by chance know how to program a VCR, do you?",
        "It’s been so long since I’ve been to the surface. How’s Blockbuster doing?",
        "I can hardly remember the last time I walked the surface. Say, did Qwikster go on to great success?",
        "You can’t get a mattress down here, so every night I dig a comfortable hole to sleep in.",
        "Hello again! Did you want to see my Yu-Gi-Oh card collection while you’re here, or are you in a rush?",
        "I’m not having the greatest day, I think I’m going to just curl up in a blanket and have a self-care day.",
        "Hey, if you’re heading back to the surface, can you check on my pizza delivery? It’s been weeks.",
        "In my time down here I’ve really got into Greek Gods. My favorite is this one that starts with an A.",
        "Thanks for visiting again. Your calm demeanor relaxes me.",
        "Even all the way down here I can’t say I’m the biggest fan of Daylight Savings Time.",
        "While I have you, I have to ask, what’s your opinion on pineapples on pizza?",
        "There’s a lot of great Reddit apps, I appreciate you using this one and hanging out with me.",
        "Quick! Do you have any last minute birthday gift ideas? Aaah!",
        "The only two social networks we get down here are Reddit and Vine.",
        "I have so many VHS reruns of Lizzie McGuire and Agent Cody Banks.",
        "I’m able to grow my own oatmeal down here. Did you want to try some?",
        "If you could interview any human living or dead, who would you choose? For me it would be Nigel Thornberry.",
    ]

    /// The line for a given visit count, per the selection above.
    /// `randomIndex` is injected so the shuffled branch is testable.
    public static func beastLine(visitCount: Int, randomIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        if visitCount <= 1 { return firstVisitLine }
        let index = visitCount - 2
        if index < beastLines.count - 1 {
            return beastLines[index]
        }
        return beastLines[min(max(randomIndex(beastLines.count), 0), beastLines.count - 1)]
    }

    /// The full attributed-text content of the cell: headline, and (from the
    /// second visit onward) the beast and its quoted line.
    ///
    /// The beast only appears when the cell is built with
    /// `likelyReachedEndOfLoadablePosts` set: Apollo's belief that you have hit
    /// the end of everything Reddit will hand out for this listing (its
    /// ~1000-item cap), not merely the end of a page. The flag selects
    /// `longHeadline` over `shortHeadline` and gates the beast passage, which
    /// is also where the visit counter is incremented.
    public static func message(likelyReachedEndOfLoadablePosts: Bool, visitCount: Int, randomIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        guard likelyReachedEndOfLoadablePosts else { return shortHeadline }
        return longHeadline + beastIntro + beastLine(visitCount: visitCount, randomIndex: randomIndex) + beastOutro
    }
}
