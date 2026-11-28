/* NSNumberFormatter: numbers as text in a locale's style and back.
 *
 * The styles: plain digits, decimal (grouped), currency (and its ISO code,
 * plural and accounting forms), percent, scientific, and English spelled
 * out and ordinal. Values are rounded on their shortest decimal digits (the
 * ones Swift prints), so 0.125 rounds as 0.125, not as the binary value
 * just under it. Locales come from a small table: the separators, currency
 * and where the currency sign and percent sign go for common ones. */

#import "FoundationInternal.h"
#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *lang, *region;     /* NULL region: any */
    const char *decimal, *group;   /* separators */
    int currencyAfter;             /* "1,00 €" rather than "€1.00" */
    int percentSpace;              /* "12 %" */
    const char *space;             /* the space before a trailing sign */
} LocaleRow;

static const LocaleRow locale_rows[] = {
    {"de", "CH", ".", "\xE2\x80\x99", 0, 0, "\xC2\xA0"},
    {"en", NULL, ".", ",", 0, 0, "\xC2\xA0"},
    {"ja", NULL, ".", ",", 0, 0, "\xC2\xA0"},
    {"zh", NULL, ".", ",", 0, 0, "\xC2\xA0"},
    {"ko", NULL, ".", ",", 0, 0, "\xC2\xA0"},
    {"de", NULL, ",", ".", 1, 1, "\xC2\xA0"},
    {"es", NULL, ",", ".", 1, 1, "\xC2\xA0"},
    {"it", NULL, ",", ".", 1, 0, "\xC2\xA0"},
    {"nl", NULL, ",", ".", 0, 0, "\xC2\xA0"},
    {"pt", NULL, ",", ".", 1, 0, "\xC2\xA0"},
    {"da", NULL, ",", ".", 1, 1, "\xC2\xA0"},
    {"tr", NULL, ",", ".", 0, 0, "\xC2\xA0"},
    {"id", NULL, ",", ".", 0, 0, "\xC2\xA0"},
    {"fr", NULL, ",", "\xE2\x80\xAF", 1, 1, "\xE2\x80\xAF"},
    {"ru", NULL, ",", "\xC2\xA0", 1, 1, "\xC2\xA0"},
    {"pl", NULL, ",", "\xC2\xA0", 1, 0, "\xC2\xA0"},
    {"sv", NULL, ",", "\xC2\xA0", 1, 1, "\xC2\xA0"},
    {"fi", NULL, ",", "\xC2\xA0", 1, 1, "\xC2\xA0"},
    {"nb", NULL, ",", "\xC2\xA0", 1, 1, "\xC2\xA0"},
    {"cs", NULL, ",", "\xC2\xA0", 1, 1, "\xC2\xA0"},
};

typedef struct {
    const char *region, *code, *symbol;
    int digits;
} CurrencyRow;

static const CurrencyRow currency_rows[] = {
    {"US", "USD", "$", 2},   {"GB", "GBP", "\xC2\xA3", 2}, {"JP", "JPY", "\xC2\xA5", 0}, {"CN", "CNY", "\xC2\xA5", 2},
    {"KR", "KRW", "\xE2\x82\xA9", 0}, {"IN", "INR", "\xE2\x82\xB9", 2}, {"CA", "CAD", "$", 2}, {"AU", "AUD", "$", 2},
    {"CH", "CHF", "CHF", 2}, {"RU", "RUB", "\xE2\x82\xBD", 2}, {"BR", "BRL", "R$", 2}, {"MX", "MXN", "$", 2},
    {"SE", "SEK", "kr", 2},  {"NO", "NOK", "kr", 2}, {"DK", "DKK", "kr.", 2}, {"PL", "PLN", "z\xC5\x82", 2},
    {"TR", "TRY", "\xE2\x82\xBA", 2}, {"CZ", "CZK", "K\xC4\x8D", 2},
    {"DE", "EUR", "\xE2\x82\xAC", 2}, {"FR", "EUR", "\xE2\x82\xAC", 2}, {"ES", "EUR", "\xE2\x82\xAC", 2},
    {"IT", "EUR", "\xE2\x82\xAC", 2}, {"NL", "EUR", "\xE2\x82\xAC", 2}, {"PT", "EUR", "\xE2\x82\xAC", 2},
    {"AT", "EUR", "\xE2\x82\xAC", 2}, {"BE", "EUR", "\xE2\x82\xAC", 2}, {"FI", "EUR", "\xE2\x82\xAC", 2},
    {"IE", "EUR", "\xE2\x82\xAC", 2}, {"GR", "EUR", "\xE2\x82\xAC", 2},
};

static const char *currency_names[][3] = {   /* code, one, other (English) */
    {"USD", "US dollar", "US dollars"}, {"EUR", "euro", "euros"}, {"GBP", "British pound", "British pounds"},
    {"JPY", "Japanese yen", "Japanese yen"}, {"CHF", "Swiss franc", "Swiss francs"}, {"CAD", "Canadian dollar", "Canadian dollars"},
    {"AUD", "Australian dollar", "Australian dollars"}, {"CNY", "Chinese yuan", "Chinese yuan"},
    {"INR", "Indian rupee", "Indian rupees"},
};

static void locale_parts(NSString *ident, char lang[8], char region[8]) {
    lang[0] = region[0] = 0;
    const char *s = ident.UTF8String ?: "";
    size_t i = 0;
    while (s[i] && s[i] != '_' && s[i] != '-' && i < 7) { lang[i] = s[i]; i++; }
    lang[i] = 0;
    const char *r = strpbrk(s, "_-");
    if (r) {
        r++;
        /* skip a script ("zh_Hans_CN") */
        const char *next = strpbrk(r, "_-");
        if (next && next - r == 4) r = next + 1;
        size_t k = 0;
        while (r[k] && r[k] != '_' && r[k] != '-' && r[k] != '@' && k < 7) { region[k] = r[k]; k++; }
        region[k] = 0;
    }
}
static const LocaleRow *locale_row(const char *lang, const char *region) {
    for (size_t i = 0; i < sizeof locale_rows / sizeof *locale_rows; i++)
        if (!strcmp(locale_rows[i].lang, lang) && (!locale_rows[i].region || !strcmp(locale_rows[i].region, region)))
            return &locale_rows[i];
    return &locale_rows[1];   /* English */
}
static const CurrencyRow *currency_for_region(const char *region) {
    for (size_t i = 0; i < sizeof currency_rows / sizeof *currency_rows; i++)
        if (!strcmp(currency_rows[i].region, region)) return &currency_rows[i];
    return NULL;
}
static const CurrencyRow *currency_for_code(NSString *code) {
    for (size_t i = 0; i < sizeof currency_rows / sizeof *currency_rows; i++)
        if ([code isEqualToString:@(currency_rows[i].code)]) return &currency_rows[i];
    return NULL;
}

/* ---- decimal digits ---- */

/* A non-negative value's shortest decimal digits: digits[0..n) with the
 * decimal point after `point` of them (point may be <= 0 or > n). */
typedef struct {
    char digits[40];
    int n, point;
} Digits;

static Digits shortest_digits(double v) {
    Digits d = {{0}, 0, 0};
    if (v == 0) {
        d.digits[0] = '0';
        d.n = 1;
        d.point = 1;
        return d;
    }
    char buf[48];
    for (int prec = 1; prec <= 17; prec++) {
        snprintf(buf, sizeof buf, "%.*e", prec - 1, v);
        if (strtod(buf, NULL) == v) break;
    }
    char *e = strchr(buf, 'e');
    int exp10 = e ? atoi(e + 1) : 0;
    for (char *p = buf; p < (e ? e : buf + strlen(buf)); p++)
        if (*p >= '0' && *p <= '9' && d.n < 39) d.digits[d.n++] = *p;
    d.point = exp10 + 1;
    return d;
}

/* Rounds to `frac` digits after the point (negative: before it). */
static void round_digits(Digits *d, int frac, NSNumberFormatterRoundingMode mode, BOOL negative) {
    int keep = d->point + frac;   /* digits kept */
    if (keep >= d->n) return;
    BOOL up;
    if (keep < 0) {
        up = (mode == NSNumberFormatterRoundCeiling && !negative) || (mode == NSNumberFormatterRoundFloor && negative) ||
             mode == NSNumberFormatterRoundUp;
        memset(d->digits, '0', 1);
        d->n = 0;
        if (up) {
            d->digits[0] = '1';
            d->n = 1;
            d->point = -frac + 1;
        } else {
            d->digits[0] = '0';
            d->n = 1;
            d->point = 1;
        }
        return;
    }
    /* what is dropped: exactly half, more, or less */
    int first = keep < d->n ? d->digits[keep] - '0' : 0;
    BOOL rest = NO;
    for (int i = keep + 1; i < d->n; i++) rest |= d->digits[i] != '0';
    BOOL any = first || rest;
    int last = keep > 0 ? d->digits[keep - 1] - '0' : 0;
    switch (mode) {
    case NSNumberFormatterRoundCeiling: up = any && !negative; break;
    case NSNumberFormatterRoundFloor: up = any && negative; break;
    case NSNumberFormatterRoundDown: up = NO; break;
    case NSNumberFormatterRoundUp: up = any; break;
    case NSNumberFormatterRoundHalfDown: up = first > 5 || (first == 5 && rest); break;
    case NSNumberFormatterRoundHalfUp: up = first >= 5; break;
    default: up = first > 5 || (first == 5 && (rest || (last & 1))); break;   /* half even */
    }
    d->n = keep;
    if (up) {
        int i = keep - 1;
        while (i >= 0 && d->digits[i] == '9') d->digits[i--] = '0';
        if (i >= 0) {
            d->digits[i]++;
        } else {
            memmove(d->digits + 1, d->digits, (size_t)d->n);
            d->digits[0] = '1';
            d->n++;
            d->point++;
        }
    }
    if (d->n == 0) {
        d->digits[0] = '0';
        d->n = 1;
        d->point = 1;
    }
}

/* ---- English words ---- */

static const char *ones_words[] = {"zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                                   "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                                   "seventeen", "eighteen", "nineteen"};
static const char *tens_words[] = {"", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"};

static void words_below_thousand(NSMutableString *s, unsigned n) {
    if (n >= 100) {
        [s appendFormat:@"%s hundred", ones_words[n / 100]];
        n %= 100;
        if (n) [s appendString:@" "];
    }
    if (n >= 20) {
        [s appendString:@(tens_words[n / 10])];
        if (n % 10) [s appendFormat:@"-%s", ones_words[n % 10]];
    } else if (n || !s.length) {
        [s appendString:@(ones_words[n])];
    }
}
static NSString *spell_integer(unsigned long long n) {
    if (n == 0) return @"zero";
    static const char *scales[] = {"", " thousand", " million", " billion", " trillion", " quadrillion", " quintillion"};
    unsigned groups[7];
    int k = 0;
    while (n) {
        groups[k++] = (unsigned)(n % 1000);
        n /= 1000;
    }
    NSMutableString *s = [NSMutableString string];
    for (int i = k - 1; i >= 0; i--) {
        if (!groups[i]) continue;
        if (s.length) [s appendString:@" "];
        NSMutableString *g = [NSMutableString string];
        words_below_thousand(g, groups[i]);
        [s appendString:g];
        [s appendString:@(scales[i])];
    }
    return s;
}

@implementation NSNumberFormatter {
    NSNumberFormatterStyle _style;
    NSLocale *_locale;
    NSInteger _minInt, _maxInt, _minFrac, _maxFrac, _minSig, _maxSig, _groupingSize, _formatWidth;
    BOOL _usesGrouping, _usesSignificant, _allowsFloats, _lenient, _generatesDecimal, _alwaysShowsDecimal;
    BOOL _minIntSet, _maxIntSet, _minFracSet, _maxFracSet, _groupingSet;
    NSNumberFormatterRoundingMode _rounding;
    NSNumber *_multiplier, *_minimum, *_maximum;
    NSString *_decimalSep, *_groupingSep, *_currencySymbol, *_currencyCode, *_intlCurrencySymbol, *_percentSymbol;
    NSString *_minusSign, *_plusSign, *_zeroSymbol, *_nilSymbol, *_nanSymbol, *_positiveInfinity, *_negativeInfinity;
    NSString *_positivePrefix, *_positiveSuffix, *_negativePrefix, *_negativeSuffix, *_positiveFormat, *_negativeFormat;
    NSString *_exponentSymbol, *_paddingCharacter;
}

- (instancetype)init {
    if ((self = [super init])) {
        _locale = [NSLocale currentLocale];
        _maxInt = 42;
        _groupingSize = 3;
        _allowsFloats = YES;
        _rounding = NSNumberFormatterRoundHalfEven;
        _maxSig = 6;
        _minSig = 1;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    NSNumberFormatter *c = [[NSNumberFormatter alloc] init];
    c.locale = _locale;
    c.numberStyle = _style;
    if (_minIntSet) c.minimumIntegerDigits = (NSUInteger)_minInt;
    if (_maxIntSet) c.maximumIntegerDigits = (NSUInteger)_maxInt;
    if (_minFracSet) c.minimumFractionDigits = (NSUInteger)_minFrac;
    if (_maxFracSet) c.maximumFractionDigits = (NSUInteger)_maxFrac;
    if (_groupingSet) c.usesGroupingSeparator = _usesGrouping;
    c.roundingMode = _rounding;
    c.multiplier = _multiplier;
    c.usesSignificantDigits = _usesSignificant;
    c.minimumSignificantDigits = _minSig;
    c.maximumSignificantDigits = _maxSig;
    c.currencyCode = _currencyCode;
    c.currencySymbol = _currencySymbol;
    c.positivePrefix = _positivePrefix;
    c.positiveSuffix = _positiveSuffix;
    c.negativePrefix = _negativePrefix;
    c.negativeSuffix = _negativeSuffix;
    c.decimalSeparator = _decimalSep;
    c.groupingSeparator = _groupingSep;
    c.zeroSymbol = _zeroSymbol;
    c.nilSymbol = _nilSymbol;
    c.minimum = _minimum;
    c.maximum = _maximum;
    c.allowsFloats = _allowsFloats;
    c.lenient = _lenient;
    c.generatesDecimalNumbers = _generatesDecimal;
    return c;
}

/* ---- the locale's defaults ---- */

- (const LocaleRow *)_row {
    char lang[8], region[8];
    locale_parts(_locale.localeIdentifier, lang, region);
    return locale_row(lang, region);
}
- (const CurrencyRow *)_currency {
    if (_currencyCode) {
        const CurrencyRow *c = currency_for_code(_currencyCode);
        if (c) return c;
    }
    char lang[8], region[8];
    locale_parts(_locale.localeIdentifier, lang, region);
    const CurrencyRow *c = currency_for_region(region);
    return c ?: currency_for_region("US");
}
- (BOOL)_isCurrency {
    return _style == NSNumberFormatterCurrencyStyle || _style == NSNumberFormatterCurrencyISOCodeStyle ||
           _style == NSNumberFormatterCurrencyPluralStyle || _style == NSNumberFormatterCurrencyAccountingStyle;
}

- (NSNumberFormatterStyle)numberStyle { return _style; }
- (void)setNumberStyle:(NSNumberFormatterStyle)s {
    _style = s;
    /* a style sets the digit counts and grouping it comes with */
    _minFracSet = _maxFracSet = _groupingSet = NO;
}
- (NSLocale *)locale { return _locale; }
- (void)setLocale:(NSLocale *)l { _locale = l ?: [NSLocale currentLocale]; }

- (NSUInteger)minimumFractionDigits {
    if (_minFracSet) return (NSUInteger)_minFrac;
    if ([self _isCurrency]) return (NSUInteger)self._currency->digits;
    return 0;
}
- (void)setMinimumFractionDigits:(NSUInteger)n {
    _minFrac = (NSInteger)n;
    _minFracSet = YES;
    if (!_maxFracSet || _maxFrac < _minFrac) {
        if (_maxFracSet || (NSInteger)self.maximumFractionDigits < _minFrac) { _maxFrac = _minFrac; _maxFracSet = YES; }
    }
}
- (NSUInteger)maximumFractionDigits {
    if (_maxFracSet) return (NSUInteger)_maxFrac;
    switch (_style) {
    case NSNumberFormatterDecimalStyle: return 3;
    case NSNumberFormatterCurrencyStyle: case NSNumberFormatterCurrencyISOCodeStyle:
    case NSNumberFormatterCurrencyPluralStyle: case NSNumberFormatterCurrencyAccountingStyle:
        return (NSUInteger)self._currency->digits;
    case NSNumberFormatterScientificStyle: return 6;
    default: return 0;
    }
}
- (void)setMaximumFractionDigits:(NSUInteger)n {
    _maxFrac = (NSInteger)n;
    _maxFracSet = YES;
    if ((NSInteger)self.minimumFractionDigits > _maxFrac) { _minFrac = _maxFrac; _minFracSet = YES; }
}
- (NSUInteger)minimumIntegerDigits { return _minIntSet ? (NSUInteger)_minInt : 1; }
- (void)setMinimumIntegerDigits:(NSUInteger)n { _minInt = (NSInteger)n; _minIntSet = YES; }
- (NSUInteger)maximumIntegerDigits { return _maxIntSet ? (NSUInteger)_maxInt : 2000000000; }
- (void)setMaximumIntegerDigits:(NSUInteger)n { _maxInt = (NSInteger)n; _maxIntSet = YES; }
- (BOOL)usesGroupingSeparator {
    if (_groupingSet) return _usesGrouping;
    return _style == NSNumberFormatterDecimalStyle || [self _isCurrency] || _style == NSNumberFormatterPercentStyle;
}
- (void)setUsesGroupingSeparator:(BOOL)b { _usesGrouping = b; _groupingSet = YES; }
- (NSUInteger)groupingSize { return (NSUInteger)_groupingSize; }
- (void)setGroupingSize:(NSUInteger)n { _groupingSize = (NSInteger)n; }
- (NSUInteger)secondaryGroupingSize { return 0; }
- (void)setSecondaryGroupingSize:(NSUInteger)n {}
- (NSNumberFormatterRoundingMode)roundingMode { return _rounding; }
- (void)setRoundingMode:(NSNumberFormatterRoundingMode)m { _rounding = m; }
- (NSNumber *)roundingIncrement { return @0; }
- (void)setRoundingIncrement:(NSNumber *)n {}
- (NSNumber *)multiplier { return _multiplier ?: (_style == NSNumberFormatterPercentStyle ? @100 : nil); }
- (void)setMultiplier:(NSNumber *)m { _multiplier = m; }
- (BOOL)usesSignificantDigits { return _usesSignificant; }
- (void)setUsesSignificantDigits:(BOOL)b { _usesSignificant = b; }
- (NSUInteger)minimumSignificantDigits { return (NSUInteger)_minSig; }
- (void)setMinimumSignificantDigits:(NSUInteger)n { _minSig = (NSInteger)n; _usesSignificant = YES; if (_maxSig < _minSig) _maxSig = _minSig; }
- (NSUInteger)maximumSignificantDigits { return (NSUInteger)_maxSig; }
- (void)setMaximumSignificantDigits:(NSUInteger)n { _maxSig = (NSInteger)n; _usesSignificant = YES; if (_minSig > _maxSig) _minSig = _maxSig; }
- (BOOL)allowsFloats { return _allowsFloats; }
- (void)setAllowsFloats:(BOOL)b { _allowsFloats = b; }
- (BOOL)isLenient { return _lenient; }
- (void)setLenient:(BOOL)b { _lenient = b; }
- (BOOL)generatesDecimalNumbers { return _generatesDecimal; }
- (void)setGeneratesDecimalNumbers:(BOOL)b { _generatesDecimal = b; }
- (BOOL)alwaysShowsDecimalSeparator { return _alwaysShowsDecimal; }
- (void)setAlwaysShowsDecimalSeparator:(BOOL)b { _alwaysShowsDecimal = b; }
- (NSUInteger)formatWidth { return (NSUInteger)_formatWidth; }
- (void)setFormatWidth:(NSUInteger)n { _formatWidth = (NSInteger)n; }
- (NSString *)paddingCharacter { return _paddingCharacter ?: @" "; }
- (void)setPaddingCharacter:(NSString *)s { _paddingCharacter = [s copy]; }
- (NSNumber *)minimum { return _minimum; }
- (void)setMinimum:(NSNumber *)n { _minimum = n; }
- (NSNumber *)maximum { return _maximum; }
- (void)setMaximum:(NSNumber *)n { _maximum = n; }

- (NSString *)decimalSeparator { return _decimalSep ?: @(self._row->decimal); }
- (void)setDecimalSeparator:(NSString *)s { _decimalSep = [s copy]; }
- (NSString *)currencyDecimalSeparator { return self.decimalSeparator; }
- (void)setCurrencyDecimalSeparator:(NSString *)s { self.decimalSeparator = s; }
- (NSString *)groupingSeparator { return _groupingSep ?: @(self._row->group); }
- (void)setGroupingSeparator:(NSString *)s { _groupingSep = [s copy]; }
- (NSString *)currencyGroupingSeparator { return self.groupingSeparator; }
- (void)setCurrencyGroupingSeparator:(NSString *)s { self.groupingSeparator = s; }
- (NSString *)currencyCode { return _currencyCode ?: @(self._currency->code); }
- (void)setCurrencyCode:(NSString *)c { _currencyCode = [c copy]; }
- (NSString *)currencySymbol {
    if (_currencySymbol) return _currencySymbol;
    const CurrencyRow *c = self._currency;
    /* a dollar outside its country says whose */
    char lang[8], region[8];
    locale_parts(_locale.localeIdentifier, lang, region);
    if (!strcmp(c->symbol, "$") && strcmp(c->region, region) && strcmp(c->code, "USD")) return @(c->code);
    if (!strcmp(c->code, "USD") && region[0] && strcmp(region, "US") && strcmp(lang, "en")) return @"$";
    return @(c->symbol);
}
- (void)setCurrencySymbol:(NSString *)s { _currencySymbol = [s copy]; }
- (NSString *)internationalCurrencySymbol { return _intlCurrencySymbol ?: self.currencyCode; }
- (void)setInternationalCurrencySymbol:(NSString *)s { _intlCurrencySymbol = [s copy]; }
- (NSString *)percentSymbol { return _percentSymbol ?: @"%"; }
- (void)setPercentSymbol:(NSString *)s { _percentSymbol = [s copy]; }
- (NSString *)perMillSymbol { return @"‰"; }
- (NSString *)minusSign { return _minusSign ?: @"-"; }
- (void)setMinusSign:(NSString *)s { _minusSign = [s copy]; }
- (NSString *)plusSign { return _plusSign ?: @"+"; }
- (void)setPlusSign:(NSString *)s { _plusSign = [s copy]; }
- (NSString *)exponentSymbol { return _exponentSymbol ?: @"E"; }
- (void)setExponentSymbol:(NSString *)s { _exponentSymbol = [s copy]; }
- (NSString *)zeroSymbol { return _zeroSymbol; }
- (void)setZeroSymbol:(NSString *)s { _zeroSymbol = [s copy]; }
- (NSString *)nilSymbol { return _nilSymbol ?: @""; }
- (void)setNilSymbol:(NSString *)s { _nilSymbol = [s copy]; }
- (NSString *)notANumberSymbol { return _nanSymbol ?: @"NaN"; }
- (void)setNotANumberSymbol:(NSString *)s { _nanSymbol = [s copy]; }
- (NSString *)positiveInfinitySymbol { return _positiveInfinity ?: @"+∞"; }
- (void)setPositiveInfinitySymbol:(NSString *)s { _positiveInfinity = [s copy]; }
- (NSString *)negativeInfinitySymbol { return _negativeInfinity ?: @"-∞"; }
- (void)setNegativeInfinitySymbol:(NSString *)s { _negativeInfinity = [s copy]; }
- (NSString *)positiveFormat { return _positiveFormat ?: @"#"; }
- (void)setPositiveFormat:(NSString *)s { _positiveFormat = [s copy]; }
- (NSString *)negativeFormat { return _negativeFormat ?: @"-#"; }
- (void)setNegativeFormat:(NSString *)s { _negativeFormat = [s copy]; }

/* The text around the digits for a sign: [prefix, suffix]. */
- (NSArray<NSString *> *)_affixesNegative:(BOOL)neg {
    const LocaleRow *row = self._row;
    NSString *sp = @(row->space);
    NSString *minus = self.minusSign;
    NSString *pre = @"", *suf = @"";
    switch (_style) {
    case NSNumberFormatterPercentStyle:
        suf = row->percentSpace ? [sp stringByAppendingString:self.percentSymbol] : self.percentSymbol;
        if (neg) pre = minus;
        break;
    case NSNumberFormatterCurrencyStyle: case NSNumberFormatterCurrencyAccountingStyle: {
        NSString *sym = self.currencySymbol;
        if (row->currencyAfter) {
            suf = [sp stringByAppendingString:sym];
            if (neg) pre = minus;
        } else {
            pre = sym;
            if (neg) pre = _style == NSNumberFormatterCurrencyAccountingStyle ? [@"(" stringByAppendingString:sym]
                                                                               : [minus stringByAppendingString:sym];
        }
        if (neg && _style == NSNumberFormatterCurrencyAccountingStyle) {
            if (row->currencyAfter) pre = @"(";
            suf = [suf stringByAppendingString:@")"];
        }
        break;
    }
    case NSNumberFormatterCurrencyISOCodeStyle:
        if (row->currencyAfter) suf = [sp stringByAppendingString:self.currencyCode];
        else pre = [self.currencyCode stringByAppendingString:sp];
        if (neg) pre = [minus stringByAppendingString:pre];
        break;
    default:
        if (neg) pre = minus;
        break;
    }
    if (neg) {
        if (_negativePrefix) pre = _negativePrefix;
        if (_negativeSuffix) suf = _negativeSuffix;
    } else {
        if (_positivePrefix) pre = _positivePrefix;
        if (_positiveSuffix) suf = _positiveSuffix;
    }
    return @[ pre, suf ];
}
- (NSString *)positivePrefix { return [self _affixesNegative:NO][0]; }
- (void)setPositivePrefix:(NSString *)s { _positivePrefix = [s copy]; }
- (NSString *)positiveSuffix { return [self _affixesNegative:NO][1]; }
- (void)setPositiveSuffix:(NSString *)s { _positiveSuffix = [s copy]; }
- (NSString *)negativePrefix { return [self _affixesNegative:YES][0]; }
- (void)setNegativePrefix:(NSString *)s { _negativePrefix = [s copy]; }
- (NSString *)negativeSuffix { return [self _affixesNegative:YES][1]; }
- (void)setNegativeSuffix:(NSString *)s { _negativeSuffix = [s copy]; }

/* ---- formatting ---- */

/* The digits of |v| laid out: integer part (grouped), separator, fraction. */
- (NSString *)_body:(double)v negative:(BOOL)neg {
    Digits d = shortest_digits(v);
    NSInteger minFrac = (NSInteger)self.minimumFractionDigits, maxFrac = MAX((NSInteger)self.maximumFractionDigits, minFrac);
    if (_usesSignificant) {
        int sigFrac = (int)_maxSig - d.point;
        round_digits(&d, sigFrac, _rounding, neg);
        int sig = 0;
        for (int i = 0; i < d.n; i++) sig = d.digits[i] != '0' || sig ? sig + 1 : 0;
        maxFrac = MAX(0, d.n - d.point);
        minFrac = MAX(0, (int)_minSig - d.point);
    } else {
        round_digits(&d, (int)maxFrac, _rounding, neg);
    }
    /* integer part */
    NSMutableString *intPart = [NSMutableString string];
    for (int i = 0; i < d.point; i++) [intPart appendFormat:@"%c", i < d.n ? d.digits[i] : '0'];
    while (intPart.length < self.minimumIntegerDigits) [intPart insertString:@"0" atIndex:0];
    if (intPart.length > self.maximumIntegerDigits)
        [intPart deleteCharactersInRange:NSMakeRange(0, intPart.length - self.maximumIntegerDigits)];
    if (self.usesGroupingSeparator && _groupingSize > 0) {
        NSString *g = self.groupingSeparator;
        for (NSInteger i = (NSInteger)intPart.length - _groupingSize; i > 0; i -= _groupingSize)
            [intPart insertString:g atIndex:(NSUInteger)i];
    }
    /* fraction */
    NSMutableString *frac = [NSMutableString string];
    for (int i = MAX(d.point, 0); i < d.n; i++) [frac appendFormat:@"%c", d.digits[i]];
    if (d.point < 0) for (int i = 0; i < -d.point; i++) [frac insertString:@"0" atIndex:0];
    while ((NSInteger)frac.length > minFrac && [frac hasSuffix:@"0"]) [frac deleteCharactersInRange:NSMakeRange(frac.length - 1, 1)];
    while ((NSInteger)frac.length < minFrac) [frac appendString:@"0"];
    if (frac.length || _alwaysShowsDecimal) {
        [intPart appendString:([self _isCurrency] ? self.currencyDecimalSeparator : self.decimalSeparator)];
        [intPart appendString:frac];
    }
    return intPart;
}
- (NSString *)_scientific:(double)v negative:(BOOL)neg {
    if (v == 0) return @"0E0";
    int exp10 = (int)floor(log10(v));
    double m = v / pow(10, exp10);
    if (m >= 10) { m /= 10; exp10++; }
    Digits d = shortest_digits(m);
    NSInteger maxFrac = _maxFracSet ? _maxFrac : 6;
    round_digits(&d, (int)maxFrac, _rounding, neg);
    if (d.point > 1) {   /* rounded up to 10 */
        exp10++;
        d.point = 1;
    }
    NSMutableString *s = [NSMutableString stringWithFormat:@"%c", d.digits[0]];
    if (d.n > 1) {
        [s appendString:self.decimalSeparator];
        for (int i = 1; i < d.n; i++) [s appendFormat:@"%c", d.digits[i]];
    }
    [s appendFormat:@"%@%d", self.exponentSymbol, exp10];
    return s;
}
- (NSString *)_spelled:(double)v {
    double ip = floor(v);
    NSMutableString *s = [NSMutableString stringWithString:spell_integer((unsigned long long)ip)];
    if (v != ip) {
        Digits d = shortest_digits(v);
        [s appendString:@" point"];
        for (int i = MAX(d.point, 0); i < d.n; i++) [s appendFormat:@" %s", ones_words[d.digits[i] - '0']];
    }
    return s;
}
- (NSString *)_ordinal:(double)v {
    long long n = llround(v);
    const char *suf = "th";
    if (n % 100 < 11 || n % 100 > 13) {
        if (n % 10 == 1) suf = "st";
        else if (n % 10 == 2) suf = "nd";
        else if (n % 10 == 3) suf = "rd";
    }
    NSNumberFormatter *plain = [NSNumberFormatter new];
    plain.locale = _locale;
    plain.numberStyle = NSNumberFormatterDecimalStyle;
    plain.maximumFractionDigits = 0;
    return [[plain stringFromNumber:@(n)] stringByAppendingString:@(suf)];
}

- (NSString *)stringFromNumber:(NSNumber *)number {
    if (!number) return _nilSymbol;
    double v = number.doubleValue;
    if (isnan(v)) return self.notANumberSymbol;
    NSNumber *mult = self.multiplier;
    if (mult) v *= mult.doubleValue;
    if (isinf(v)) return v > 0 ? self.positiveInfinitySymbol : self.negativeInfinitySymbol;
    if (v == 0 && _zeroSymbol) return _zeroSymbol;
    BOOL neg = signbit(v) && v != 0;
    double a = fabs(v);
    NSString *body;
    switch (_style) {
    case NSNumberFormatterScientificStyle: body = [self _scientific:a negative:neg]; break;
    case NSNumberFormatterSpellOutStyle: body = [self _spelled:a]; break;
    case NSNumberFormatterOrdinalStyle: body = [self _ordinal:a]; break;
    default: body = [self _body:a negative:neg]; break;
    }
    if (_style == NSNumberFormatterSpellOutStyle) return neg ? [@"minus " stringByAppendingString:body] : body;
    if (_style == NSNumberFormatterOrdinalStyle) return neg ? [self.minusSign stringByAppendingString:body] : body;
    /* a value that rounds to zero shows no sign */
    if (neg && [body rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"123456789"]].location == NSNotFound)
        neg = NO;
    if (_style == NSNumberFormatterCurrencyPluralStyle) {
        NSString *code = self.currencyCode, *name = code;
        for (size_t i = 0; i < sizeof currency_names / sizeof *currency_names; i++)
            if ([code isEqualToString:@(currency_names[i][0])]) name = @(currency_names[i][a == 1 ? 1 : 2]);
        return [NSString stringWithFormat:@"%@%@ %@", neg ? self.minusSign : @"", body, name];
    }
    NSArray *aff = [self _affixesNegative:neg];
    NSString *out = [NSString stringWithFormat:@"%@%@%@", aff[0], body, aff[1]];
    if (_formatWidth > 0 && (NSInteger)out.length < _formatWidth) {
        NSMutableString *pad = [NSMutableString string];
        while ((NSInteger)(pad.length + out.length) < _formatWidth) [pad appendString:self.paddingCharacter];
        out = [pad stringByAppendingString:out];
    }
    return out;
}
- (NSString *)stringForObjectValue:(id)obj {
    if ([obj isKindOfClass:[NSNumber class]]) return [self stringFromNumber:obj];
    return nil;
}
+ (NSString *)localizedStringFromNumber:(NSNumber *)num numberStyle:(NSNumberFormatterStyle)style {
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.numberStyle = style;
    return [f stringFromNumber:num];
}

/* ---- parsing ---- */

- (NSNumber *)numberFromString:(NSString *)string {
    if (!string) return nil;
    NSMutableString *s = [string mutableCopy];
    if (_lenient)
        [s setString:[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    if (_zeroSymbol && [s isEqualToString:_zeroSymbol]) return @0;
    if (_style == NSNumberFormatterSpellOutStyle || _style == NSNumberFormatterOrdinalStyle) {
        if (_style == NSNumberFormatterOrdinalStyle) {
            for (NSString *suf in @[ @"st", @"nd", @"rd", @"th" ])
                if ([s hasSuffix:suf]) { [s deleteCharactersInRange:NSMakeRange(s.length - 2, 2)]; break; }
        } else {
            return nil;
        }
    }
    BOOL neg = NO, matched = NO;
    for (int sign = 1; sign >= 0 && !matched; sign--) {
        NSArray *aff = [self _affixesNegative:sign == 1];
        NSString *pre = aff[0], *suf = aff[1];
        if ((pre.length || suf.length) && [s hasPrefix:pre] && [s hasSuffix:suf] && s.length >= pre.length + suf.length) {
            [s setString:[s substringWithRange:NSMakeRange(pre.length, s.length - pre.length - suf.length)]];
            neg = sign == 1;
            matched = YES;
        }
    }
    if (!matched && [s hasPrefix:self.minusSign]) {
        [s deleteCharactersInRange:NSMakeRange(0, self.minusSign.length)];
        neg = YES;
    } else if (!matched && [s hasPrefix:self.plusSign]) {
        [s deleteCharactersInRange:NSMakeRange(0, self.plusSign.length)];
    }
    if (_lenient) {
        [s setString:[s stringByReplacingOccurrencesOfString:self.currencySymbol withString:@""]];
        [s setString:[s stringByReplacingOccurrencesOfString:self.percentSymbol withString:@""]];
        [s setString:[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    }
    NSString *g = self.groupingSeparator;
    if (g.length) [s setString:[s stringByReplacingOccurrencesOfString:g withString:@""]];
    NSString *dsep = self.decimalSeparator;
    if (dsep.length && ![dsep isEqualToString:@"."]) {
        if ([s rangeOfString:@"."].location != NSNotFound) return nil;
        [s setString:[s stringByReplacingOccurrencesOfString:dsep withString:@"."]];
    }
    if (_style == NSNumberFormatterScientificStyle)
        [s setString:[s stringByReplacingOccurrencesOfString:self.exponentSymbol withString:@"e"]];
    const char *c = s.UTF8String;
    if (!c || !*c) return nil;
    for (const char *p = c; *p; p++)
        if (!((*p >= '0' && *p <= '9') || *p == '.' || ((*p == 'e' || *p == '-' || *p == '+') &&
                                                          _style == NSNumberFormatterScientificStyle)))
            return nil;
    char *end = NULL;
    double v = strtod(c, &end);
    if (!end || *end) return nil;
    if (neg) v = -v;
    NSNumber *mult = self.multiplier;
    if (mult && mult.doubleValue != 0) v /= mult.doubleValue;
    if (!_allowsFloats && v != floor(v)) return nil;
    if (_minimum && v < _minimum.doubleValue) return nil;
    if (_maximum && v > _maximum.doubleValue) return nil;
    if (_generatesDecimal) return [NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%.17g", v]];
    if (v == floor(v) && fabs(v) < 9.2e18) return @((long long)v);
    return @(v);
}
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error {
    NSNumber *n = [self numberFromString:string];
    if (obj) *obj = n;
    if (!n && error) *error = @"Invalid number";
    return n != nil;
}
@end
