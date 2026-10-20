pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// App search for the launcher. Everything is in memory (DesktopEntries), and
// launch counts (~/.local/state/nothing/launcher.json) boost frequent apps.
// "launcher.favorites" in config.json is pinned to the front of the opening
// grid; "launcher.hidden" removes apps entirely. Both accept a desktop name
// (e.g. "Firefox") or its id (e.g. "firefox").
Singleton {
    id: root

    function list(key) {
        const v = Config.get(key);
        return Array.isArray(v) ? v : [];
    }
    function matches(a, value) {
        const v = String(value).toLowerCase();
        return a.id.toLowerCase() === v || a.name.toLowerCase() === v;
    }

    readonly property var hidden: list("launcher.hidden")
    readonly property var favorites: list("launcher.favorites")

    readonly property var all: DesktopEntries.applications.values
        .filter(a => !a.noDisplay && !hidden.some(h => matches(a, h)))
        .sort((a, b) => a.name.localeCompare(b.name))
    property var counts: ({})
    property var recent: [] // app ids, most recently launched first

    // Opening grid: favorites in the configured order, then recently launched
    // apps. With no favorites, show every app with recent/most-used first.
    // Typing searches every non-hidden app.
    readonly property var byUse: {
        const out = [];
        const seen = new Set();
        for (const f of favorites) {
            const a = all.find(x => matches(x, f) && !seen.has(x.id));
            if (a) {
                seen.add(a.id);
                out.push(a);
            }
        }

        if (!favorites.length) {
            const rest = all.filter(a => !seen.has(a.id));
            rest.sort((a, b) => {
                const ra = recent.indexOf(a.id);
                const rb = recent.indexOf(b.id);
                if ((ra >= 0) !== (rb >= 0))
                    return ra >= 0 ? -1 : 1;
                if (ra >= 0 && ra !== rb)
                    return ra - rb;
                return (counts[b.id] ?? 0) - (counts[a.id] ?? 0) || a.name.localeCompare(b.name);
            });
            return out.concat(rest);
        }

        // Favorites are configured: fill the rest with recent apps only.
        let recents = 0;
        for (const id of recent) {
            const a = all.find(x => x.id === id && !seen.has(x.id));
            if (a) {
                seen.add(a.id);
                out.push(a);
                recents++;
            }
        }
        if (!recents) {
            // First run with this file: use the old most-used list once.
            const used = all.filter(a => !seen.has(a.id) && (counts[a.id] ?? 0) > 0)
                .sort((a, b) => (counts[b.id] ?? 0) - (counts[a.id] ?? 0) || a.name.localeCompare(b.name));
            for (const a of used) {
                seen.add(a.id);
                out.push(a);
            }
        }
        return out;
    }

    function fuzzy(text, q) {
        let i = 0;
        for (const ch of text)
            if (ch === q[i] && ++i === q.length)
                return true;
        return false;
    }
    function score(a, q) {
        const n = a.name.toLowerCase();
        let s = 0;
        if (n === q) s = 1000;
        else if (n.startsWith(q)) s = 800;
        else if (n.split(/[\s\-_.]+/).some(w => w.startsWith(q))) s = 600;
        else if (n.includes(q)) s = 450;
        else if ((a.genericName ?? "").toLowerCase().includes(q)) s = 300;
        else if (((a.keywords ?? "") + " " + (a.categories ?? "")).toLowerCase().includes(q)) s = 220;
        else if (q.length > 1 && fuzzy(n, q)) s = 150;
        else if ((a.execString ?? "").toLowerCase().includes(q)) s = 100;
        return s ? s + Math.min(150, (counts[a.id] ?? 0) * 6) : 0;
    }
    function search(query) {
        const q = query.trim().toLowerCase();
        if (!q)
            return byUse;
        return all.map(a => ({ a: a, s: score(a, q) }))
            .filter(x => x.s > 0)
            .sort((x, y) => y.s - x.s)
            .map(x => x.a);
    }

    function launch(app, action) {
        const c = Object.assign({}, counts);
        c[app.id] = (c[app.id] ?? 0) + 1;
        counts = c;
        store.setText(JSON.stringify(c));

        const history = recent.length ? recent
            : Object.keys(counts).sort((a, b) => (counts[b] ?? 0) - (counts[a] ?? 0));
        recent = [app.id].concat(history.filter(id => id !== app.id)).slice(0, 50);
        recentStore.setText(JSON.stringify(recent));

        if (action)
            action.execute();
        else if (app.runInTerminal)
            Quickshell.execDetached(["kitty", "-1", "--instance-group", "nothing", "--"].concat(app.command));
        else
            app.execute();
    }

    FileView {
        id: store
        path: Theme.stateDir + "/launcher.json"
        onLoaded: {
            try { root.counts = JSON.parse(text()); } catch (e) {}
        }
    }
    FileView {
        id: recentStore
        path: Theme.stateDir + "/launcher-recent.json"
        onLoaded: {
            try {
                const v = JSON.parse(text());
                if (Array.isArray(v))
                    root.recent = v.filter(id => typeof id === "string");
            } catch (e) {}
        }
    }
}
