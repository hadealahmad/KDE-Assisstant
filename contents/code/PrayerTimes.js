/*
 * KDE Assistant — PrayerTimes.js
 * Local Hijri (Umm al-Qura) calendar calculation and date/time context builder.
 *
 * The Hijri algorithm is based on the tabular Islamic calendar (Type II)
 * with seasonal adjustment, suitable for general-purpose use. It does not
 * rely on moon sighting or any external API.
 */

.pragma library

// ──────────────────────────────────────────────
// Hijri month names
// ──────────────────────────────────────────────

var _hijriMonths = [
    "Muharram", "Safar", "Rabi al-Awwal", "Rabi al-Thani",
    "Jumada al-Ula", "Jumada al-Thani", "Rajab", "Sha'ban",
    "Ramadan", "Shawwal", "Dhu al-Qa'dah", "Dhu al-Hijjah"
];

var _hijriMonthsAr = [
    "محرّم", "صفر", "ربيع الأول", "ربيع الثاني",
    "جمادى الأولى", "جمادى الثانية", "رجب", "شعبان",
    "رمضان", "شوال", "ذو القعدة", "ذو الحجة"
];

var _gregDays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

// ──────────────────────────────────────────────
// Tabular Hijri calendar helpers (Type II)
// ──────────────────────────────────────────────

function _hijriLeapYear(year) {
    return ((11 * year + 14) % 30) < 11;
}

function _hijriDaysInYear(year) {
    return _hijriLeapYear(year) ? 355 : 354;
}

function _hijriDaysInMonth(month, year) {
    if (month % 2 === 1) return 30;
    if (month < 12) return 29;
    return _hijriLeapYear(year) ? 30 : 29;
}

// Julian Day Number from Gregorian date
function _gregorianToJDN(year, month, day) {
    var a = Math.floor((14 - month) / 12);
    var y = year + 4800 - a;
    var m = month + 12 * a - 3;
    return day + Math.floor((153 * m + 2) / 5) + 365 * y +
           Math.floor(y / 4) - Math.floor(y / 100) + Math.floor(y / 400) - 32045;
}

// Gregorian date from Julian Day Number
function _jdnToGregorian(jdn) {
    var a = jdn + 32044;
    var b = Math.floor((4 * a + 3) / 146097);
    var c = a - Math.floor(146097 * b / 4);
    var d = Math.floor((4 * c + 3) / 1461);
    var e = c - Math.floor(1461 * d / 4);
    var m = Math.floor((5 * e + 2) / 153);

    var day = e - Math.floor((153 * m + 2) / 5) + 1;
    var month = m + 3 - 12 * Math.floor(m / 10);
    var year = 100 * b + d - 4800 + Math.floor(m / 10);

    return { year: year, month: month, day: day };
}

// Hijri date from Julian Day Number
function _jdnToHijri(jdn) {
    var l = jdn - 1948440 + 10632;
    var n = Math.floor((l - 1) / 10631);
    var remainder = l - 10631 * n + 354;
    var j = Math.floor((10985 - remainder) / 5316) * Math.floor((50 * remainder) / 17719) +
            Math.floor(remainder / 5670) * Math.floor((43 * remainder) / 15238);
    remainder = remainder - Math.floor((30 - j) / 15) * Math.floor((17719 * j) / 50) -
                Math.floor(j / 16) * Math.floor((15238 * j) / 43) + 29;

    var month = Math.floor((24 * remainder) / 709);
    var day = remainder - Math.floor((709 * month) / 24);
    var year = 30 * n + j - 30;

    return { year: year, month: month, day: day };
}

// Hijri date from Gregorian date
function _gregorianToHijri(year, month, day) {
    var jdn = _gregorianToJDN(year, month, day);
    return _jdnToHijri(jdn);
}

// ──────────────────────────────────────────────
// Public API
// ──────────────────────────────────────────────

/**
 * Get Hijri date for today.
 * Returns { year, month, day, monthName, monthNameAr }
 */
function getHijriDate(date) {
    var d = date || new Date();
    var hijri = _gregorianToHijri(d.getFullYear(), d.getMonth() + 1, d.getDate());
    return {
        year: hijri.year,
        month: hijri.month,
        day: hijri.day,
        monthName: _hijriMonths[hijri.month - 1] || "",
        monthNameAr: _hijriMonthsAr[hijri.month - 1] || ""
    };
}

/**
 * Get formatted Gregorian date/time info.
 * Returns { dayName, date, time, timezone, full }
 */
function getGregorianDate(date) {
    var d = date || new Date();
    var dayName = _gregDays[d.getDay()];
    var year = d.getFullYear();
    var month = d.getMonth() + 1;
    var day = d.getDate();
    var hours = d.getHours();
    var minutes = d.getMinutes();

    var monthStr = month < 10 ? "0" + month : "" + month;
    var dayStr = day < 10 ? "0" + day : "" + day;
    var hStr = hours < 10 ? "0" + hours : "" + hours;
    var mStr = minutes < 10 ? "0" + minutes : "" + minutes;

    var tz = "";
    try {
        tz = Intl.DateTimeFormat().resolvedOptions().timeZone || "";
    } catch (e) {
        // Fallback: extract from toString
        var tzMatch = d.toString().match(/\(([^)]+)\)/);
        if (tzMatch) tz = tzMatch[1];
    }

    return {
        dayName: dayName,
        date: dayStr + "/" + monthStr + "/" + year,
        time: hStr + ":" + mStr,
        timezone: tz,
        full: dayName + ", " + day + " " + _monthName(month) + " " + year + ", " + hStr + ":" + mStr + (tz ? " (" + tz + ")" : "")
    };
}

function _monthName(m) {
    var names = ["January", "February", "March", "April", "May", "June",
                 "July", "August", "September", "October", "November", "December"];
    return names[m - 1] || "";
}

/**
 * Build a date/time context block for the system prompt.
 * Includes both Gregorian and Hijri dates.
 */
function buildDateTimeContext() {
    var now = new Date();
    var greg = getGregorianDate(now);
    var hijri = getHijriDate(now);

    return "## Current Date & Time\n" +
           "Gregorian: " + greg.full + "\n" +
           "Hijri: " + hijri.day + " " + hijri.monthName + " " + hijri.year + " AH";
}

/**
 * Build prayer times section for the system prompt.
 * @param {number} lat - Latitude
 * @param {number} lng - Longitude
 * @param {number} method - Calculation method (2=MWL, 3=ISNA, 4=UmmAlQura, 5=Egyptian, etc.)
 */
function buildPrayerTimesInstructions(lat, lng, method) {
    var locationLine = "";
    if (typeof lat === "number" && typeof lng === "number" && !isNaN(lat) && !isNaN(lng)) {
        locationLine = "User's default location: latitude=" + lat + ", longitude=" + lng + "\n";
    } else {
        locationLine = "User's default location: not configured. Ask the user for their city or coordinates.\n";
    }

    var methodLine = "";
    if (typeof method === "number" && method > 0) {
        var methodName = _methodName(method);
        methodLine = "Default calculation method: " + method + " (" + methodName + ")\n";
    } else {
        methodLine = "Default calculation method: not configured. Use method 3 (ISNA) as fallback.\n";
    }

    return "\n## Prayer Times (Islamic)\n" +
           "To fetch prayer times for the user, use the [FETCH:] tool with the AlAdhan API.\n" +
           "URL format: https://api.aladhan.com/v1/timings/today?latitude={lat}&longitude={lng}&method={method}\n\n" +
           locationLine +
           methodLine +
           "Calculation methods:\n" +
           "  2 = Muslim World League (MWL)\n" +
           "  3 = Islamic Society of North America (ISNA)\n" +
           "  4 = Umm Al-Qura University, Makkah\n" +
           "  5 = Egyptian General Authority of Survey\n" +
           "  7 = Institute of Geophysics, University of Tehran\n" +
           "  8 = Gulf Region\n" +
           "  9 = Kuwait\n" +
           "  10 = Qatar\n" +
           "  11 = MUIS, Singapore\n" +
           "  13 = Diyanet, Turkey\n" +
           "  15 = Moonsighting Committee Worldwide\n\n" +
           "Examples:\n" +
           "  [FETCH: https://api.aladhan.com/v1/timings/today?latitude=52.52&longitude=13.405&method=3]\n" +
           "  [FETCH: https://api.aladhan.com/v1/timings/2026-06-19?latitude=21.4225&longitude=39.8262&method=4]\n\n" +
           "For monthly timetable, use:\n" +
           "  https://api.aladhan.com/v1/calendar/{year}/{month}?latitude={lat}&longitude={lng}&method={method}\n\n" +
           "The API returns JSON with a 'data.timings' object containing: Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha, and others.\n" +
           "Format the response as a clean table or list for the user.";
}

function _methodName(method) {
    var names = {
        1: "University of Islamic Sciences, Karachi",
        2: "Muslim World League (MWL)",
        3: "Islamic Society of North America (ISNA)",
        4: "Umm Al-Qura University, Makkah",
        5: "Egyptian General Authority of Survey",
        7: "Institute of Geophysics, University of Tehran",
        8: "Gulf Region",
        9: "Kuwait",
        10: "Qatar",
        11: "MUIS, Singapore",
        12: "UOIF, France",
        13: "Diyanet, Turkey",
        15: "Moonsighting Committee Worldwide"
    };
    return names[method] || "Unknown";
}
