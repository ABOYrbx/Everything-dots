pragma Singleton

import QtQuick
import Quickshell

// English date names.
//
// The shell always speaks English, whatever locale the session runs in.
// Qt.formatDateTime() would follow the system locale and print "Montag" or
// "19. Oktober", and Date.toLocaleDateString() cannot be given a Qt format
// string. So the names live here and the dates are built by hand.
//
// Named "Dates" and not "Locale": QML has a built-in Locale type, and a
// singleton with that name would be shadowed by it.
Singleton {
    id: root

    readonly property var months: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    readonly property var weekdays: [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]

    // "October"
    function month(d) {
        return months[d.getMonth()];
    }

    // "Monday" - the week starts on Monday, like the calendar grid does.
    function weekday(d) {
        return weekdays[(d.getDay() + 6) % 7];
    }

    // "19 October"
    function dayMonth(d) {
        return d.getDate() + " " + month(d);
    }

    // "October 2026"
    function monthYear(d) {
        return month(d) + " " + d.getFullYear();
    }

    // "Monday, 19 October"
    function longDate(d) {
        return weekday(d) + ", " + dayMonth(d);
    }
}
