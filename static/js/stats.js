let consecutiveStatsFailures = 0;
let lastSystemStatsAll = null;
const STATS_UNAVAILABLE_THRESHOLD = 3;

export function formatUptime(seconds) {
    const totalSeconds = Math.max(0, Number(seconds) || 0);
    const days = Math.floor(totalSeconds / 86400);
    const hours = Math.floor((totalSeconds % 86400) / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);

    if (days > 0) return `${days}d ${hours}h ${minutes}m`;
    if (hours > 0) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
}

export function formatBytes(bytes) {
    const value = Number(bytes);
    if (!Number.isFinite(value) || value <= 0) return null;
    const gb = value / 1024 ** 3;
    if (gb >= 1) return `${gb.toFixed(1)} GB`;
    const mb = value / 1024 ** 2;
    return `${mb.toFixed(0)} MB`;
}

function metricEl(className, hostId) {
    return document.querySelector(`.${className}[data-host-id="${hostId}"]`);
}

function applyHostStats(hostId, payload) {
    const uptimeEl = metricEl("metrics-uptime", hostId);
    const ramEl = metricEl("metrics-ram", hostId);
    const cpuEl = metricEl("metrics-cpu", hostId);
    const diskEl = metricEl("metrics-disk", hostId);
    const uptimeFooterEl = metricEl("metrics-uptime-footer", hostId);
    const ramFooterEl = metricEl("metrics-ram-footer", hostId);
    const cpuFooterEl = metricEl("metrics-cpu-footer", hostId);
    const diskFooterEl = metricEl("metrics-disk-footer", hostId);
    const hostnameEl = document.querySelector(`.metrics-hostname[data-host-id="${hostId}"]`);

    if (!uptimeEl || !ramEl || !cpuEl || !diskEl) return;

    const stats = payload?.stats;
    if (hostnameEl && payload?.hostname) {
        hostnameEl.textContent = payload.hostname;
    }

    if (!stats) {
        const message = payload?.error || "Unavailable";
        uptimeEl.textContent = message;
        ramEl.textContent = message;
        cpuEl.textContent = message;
        diskEl.textContent = message;
        if (uptimeFooterEl) uptimeFooterEl.textContent = "";
        if (ramFooterEl) ramFooterEl.textContent = "";
        if (cpuFooterEl) cpuFooterEl.textContent = "";
        if (diskFooterEl) diskFooterEl.textContent = "";
        return;
    }

    uptimeEl.textContent = formatUptime(stats?.uptime_seconds);
    if (uptimeFooterEl) {
        const upSec = stats?.uptime_seconds || 0;
        const startDate = new Date(Date.now() - upSec * 1000);
        uptimeFooterEl.textContent = startDate.toLocaleString();
    }

    const ramPercent = stats?.memory?.percent;
    const ramUsed = formatBytes(stats?.memory?.used_bytes);
    const ramTotal = formatBytes(stats?.memory?.total_bytes);
    ramEl.textContent =
        typeof ramPercent === "number" ? `${ramPercent.toFixed(1)}%` : "Unavailable";
    if (ramFooterEl) {
        ramFooterEl.textContent = ramUsed && ramTotal ? `${ramUsed} / ${ramTotal}` : "";
    }

    const cpuPercent = stats?.cpu?.percent;
    const cores = stats?.cpu?.cores;
    const maxHz = stats?.cpu?.max_hz;
    const tempCelsius = stats?.cpu?.temperature_celsius;
    cpuEl.textContent =
        typeof cpuPercent === "number" ? `${cpuPercent.toFixed(1)}%` : "Warming up...";
    if (cpuFooterEl) {
        const details = [];
        if (cores) details.push(`${cores} cores`);
        if (typeof maxHz === "number") details.push(`${(maxHz / 1e9).toFixed(2)} GHz`);
        if (typeof tempCelsius === "number") details.push(`${tempCelsius}°C`);
        cpuFooterEl.textContent = details.join(" \u00b7 ");
    }

    const diskPercent = stats?.disk?.percent;
    const diskUsed = formatBytes(stats?.disk?.used_bytes);
    const diskTotal = formatBytes(stats?.disk?.total_bytes);
    diskEl.textContent =
        typeof diskPercent === "number" ? `${diskPercent.toFixed(1)}%` : "Unavailable";
    if (diskFooterEl) {
        diskFooterEl.textContent =
            diskUsed && diskTotal ? `${diskUsed} / ${diskTotal}` : "";
    }
}

function applyAllHosts(hosts) {
    if (!Array.isArray(hosts)) return;
    for (const entry of hosts) {
        if (entry?.id) applyHostStats(entry.id, entry);
    }
}

export async function updateSystemStats() {
    const hostSections = document.querySelectorAll(".metrics-host-section[data-host-id]");
    if (!hostSections.length) return;

    try {
        const res = await fetch(`/api/system-stats/all?t=${Date.now()}`, {
            method: "GET",
            cache: "no-store",
        });
        if (!res.ok) throw new Error("system stats endpoint failed");

        const payload = await res.json();
        consecutiveStatsFailures = 0;
        lastSystemStatsAll = payload;
        applyAllHosts(payload?.hosts);
    } catch {
        consecutiveStatsFailures++;

        if (consecutiveStatsFailures >= STATS_UNAVAILABLE_THRESHOLD) {
            hostSections.forEach((section) => {
                const hostId = section.getAttribute("data-host-id");
                applyHostStats(hostId, { error: "Unavailable" });
            });
        } else if (lastSystemStatsAll) {
            applyAllHosts(lastSystemStatsAll.hosts);
        }
    }
}
