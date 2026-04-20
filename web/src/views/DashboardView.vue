<script setup lang="ts">
import { computed, onMounted, watch, defineComponent, h } from 'vue'
import {
    SyvoraCard,
    SyvoraBadge,
    SyvoraEmptyState,
} from '@syvora/ui'
import { useAuth } from '../composables/useAuth'
import { useProfile } from '../composables/useProfile'
import { useMandator } from '../composables/useMandator'
import {
    useDashboard,
    type UpcomingItem,
    type CostItem,
    type StatusBreakdown,
    type ItemStatus,
} from '../composables/useDashboard'

const { user } = useAuth()
const { profile } = useProfile()
const { mandator } = useMandator()
const {
    loading,
    upcoming,
    topByCost,
    totalCost,
    certStatusBreakdown,
    licenseStatusBreakdown,
    refresh,
} = useDashboard()

const greeting = computed(() => {
    const name = profile.value?.display_name || user.value?.email || 'there'
    return `Welcome, ${name}`
})

const isTotallyEmpty = computed(() =>
    certStatusBreakdown.value.total === 0
    && licenseStatusBreakdown.value.total === 0,
)

const expiring30Combined = computed(() =>
    certStatusBreakdown.value.expiring + licenseStatusBreakdown.value.expiring,
)

const maxCost = computed(() => topByCost.value.reduce((m, i) => Math.max(m, i.cost), 0))

const currency = new Intl.NumberFormat('de-CH', {
    style: 'currency',
    currency: 'CHF',
    minimumFractionDigits: 2,
})

function formatCurrency(value: number): string {
    return currency.format(value)
}

function formatDate(dateStr: string): string {
    return new Date(dateStr).toLocaleDateString(undefined, {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
    })
}

function daysUntil(dateStr: string): number {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const target = new Date(dateStr)
    target.setHours(0, 0, 0, 0)
    return Math.floor((target.getTime() - today.getTime()) / (1000 * 60 * 60 * 24))
}

function daysLabel(dateStr: string): string {
    const days = daysUntil(dateStr)
    if (days < 0) return `${Math.abs(days)} day${Math.abs(days) === 1 ? '' : 's'} overdue`
    if (days === 0) return 'today'
    return `in ${days} day${days === 1 ? '' : 's'}`
}

function statusVariant(status: ItemStatus): 'success' | 'warning' | 'error' {
    if (status === 'expired') return 'error'
    if (status === 'expiring') return 'warning'
    return 'success'
}

function statusLabel(status: ItemStatus): string {
    if (status === 'expired') return 'Expired'
    if (status === 'expiring') return 'Expiring'
    return 'Valid'
}

function typeLabel(t: 'certificate' | 'license'): string {
    return t === 'license' ? 'License' : 'Cert'
}

function responsibleLabel(item: UpcomingItem): string {
    if (!item.responsible) return '—'
    return item.responsible.display_name || item.responsible.email
}

function barFill(item: CostItem): string {
    if (maxCost.value <= 0) return '0%'
    return `${(item.cost / maxCost.value) * 100}%`
}

const StatusSparkline = defineComponent({
    props: {
        breakdown: { type: Object as () => StatusBreakdown, required: true },
    },
    setup(props) {
        return () => {
            const { valid, expiring, expired, total } = props.breakdown
            if (total === 0) {
                return h('div', { class: 'spark spark--empty' })
            }
            const widths = [
                { cls: 'spark-seg--valid', part: valid },
                { cls: 'spark-seg--expiring', part: expiring },
                { cls: 'spark-seg--expired', part: expired },
            ]
            return h(
                'div',
                { class: 'spark' },
                widths.map((w) =>
                    h('div', {
                        class: ['spark-seg', w.cls],
                        style: { width: `${(w.part / total) * 100}%` },
                        title: `${w.part}`,
                    }),
                ),
            )
        }
    },
})

const StatusBar = defineComponent({
    props: {
        label: { type: String, required: true },
        breakdown: { type: Object as () => StatusBreakdown, required: true },
    },
    setup(props) {
        return () => {
            const { valid, expiring, expired, total } = props.breakdown
            return h('div', { class: 'statbar' }, [
                h('div', { class: 'statbar-label' }, props.label),
                total === 0
                    ? h('div', { class: 'statbar-track statbar-track--empty' }, 'No data')
                    : h('div', { class: 'statbar-track' }, [
                        h('div', {
                            class: 'statbar-seg statbar-seg--valid',
                            style: { width: `${(valid / total) * 100}%` },
                            title: `${valid} valid`,
                        }),
                        h('div', {
                            class: 'statbar-seg statbar-seg--expiring',
                            style: { width: `${(expiring / total) * 100}%` },
                            title: `${expiring} expiring`,
                        }),
                        h('div', {
                            class: 'statbar-seg statbar-seg--expired',
                            style: { width: `${(expired / total) * 100}%` },
                            title: `${expired} expired`,
                        }),
                    ]),
                h('div', { class: 'statbar-legend' }, [
                    h('span', {}, `${valid} valid`),
                    h('span', { class: 'statbar-sep' }, '·'),
                    h('span', {}, `${expiring} expiring`),
                    h('span', { class: 'statbar-sep' }, '·'),
                    h('span', {}, `${expired} expired`),
                ]),
            ])
        }
    },
})

async function loadAll() {
    if (!mandator.value) return
    await refresh(mandator.value.id)
}

onMounted(loadAll)
watch(() => mandator.value?.id, loadAll)
</script>

<template>
    <div class="dash">
        <header class="dash-greeting">
            <h1>{{ greeting }}</h1>
            <p v-if="mandator" class="dash-org">{{ mandator.name }}</p>
        </header>

        <div v-if="loading && isTotallyEmpty" class="dash-loading">Loading...</div>

        <SyvoraEmptyState v-else-if="isTotallyEmpty">
            Get started by adding your first
            <RouterLink to="/certificates" class="dash-link">certificate</RouterLink>
            or
            <RouterLink to="/licenses" class="dash-link">license</RouterLink>.
        </SyvoraEmptyState>

        <template v-else>
            <!-- Stat cards -->
            <div class="dash-stats">
                <RouterLink to="/certificates" class="dash-stat-link">
                    <SyvoraCard>
                        <div class="dash-stat">
                            <span class="dash-stat-label">Certificates</span>
                            <span class="dash-stat-value">{{ certStatusBreakdown.total }}</span>
                            <StatusSparkline :breakdown="certStatusBreakdown" />
                        </div>
                    </SyvoraCard>
                </RouterLink>

                <RouterLink to="/licenses" class="dash-stat-link">
                    <SyvoraCard>
                        <div class="dash-stat">
                            <span class="dash-stat-label">Licenses</span>
                            <span class="dash-stat-value">{{ licenseStatusBreakdown.total }}</span>
                            <StatusSparkline :breakdown="licenseStatusBreakdown" />
                        </div>
                    </SyvoraCard>
                </RouterLink>

                <SyvoraCard>
                    <div class="dash-stat">
                        <span class="dash-stat-label">Expiring in 30 days</span>
                        <span class="dash-stat-value dash-stat-value--warn">{{ expiring30Combined }}</span>
                    </div>
                </SyvoraCard>

                <SyvoraCard>
                    <div class="dash-stat">
                        <span class="dash-stat-label">Total cost</span>
                        <span class="dash-stat-value dash-stat-value--cost">{{ formatCurrency(totalCost) }}</span>
                    </div>
                </SyvoraCard>
            </div>

            <!-- Expiring soon -->
            <SyvoraCard title="Expiring in the next 60 days">
                <div v-if="upcoming.length === 0" class="dash-padded">
                    <SyvoraEmptyState>Nothing expiring in the next 60 days.</SyvoraEmptyState>
                </div>
                <div v-else class="dash-upcoming">
                    <RouterLink
                        v-for="item in upcoming.slice(0, 20)"
                        :key="`${item.type}-${item.id}`"
                        :to="item.href"
                        class="dash-upcoming-row"
                    >
                        <SyvoraBadge>{{ typeLabel(item.type) }}</SyvoraBadge>
                        <div class="dash-upcoming-main">
                            <span class="dash-upcoming-name">{{ item.name }}</span>
                            <span class="dash-upcoming-meta">{{ responsibleLabel(item) }}</span>
                        </div>
                        <div class="dash-upcoming-date">
                            <span>{{ formatDate(item.expires_at) }}</span>
                            <span class="dash-upcoming-days">{{ daysLabel(item.expires_at) }}</span>
                        </div>
                        <SyvoraBadge :variant="statusVariant(item.status)">
                            {{ statusLabel(item.status) }}
                        </SyvoraBadge>
                    </RouterLink>
                </div>
            </SyvoraCard>

            <!-- Cost breakdown -->
            <SyvoraCard title="Top 10 items by cost">
                <div v-if="topByCost.length === 0" class="dash-padded">
                    <SyvoraEmptyState>
                        No cost data yet. Add cost to a certificate or license to see it here.
                    </SyvoraEmptyState>
                </div>
                <div v-else class="dash-cost">
                    <RouterLink
                        v-for="item in topByCost"
                        :key="`${item.type}-${item.id}`"
                        :to="item.href"
                        class="dash-cost-row"
                    >
                        <div class="dash-cost-header">
                            <SyvoraBadge>{{ typeLabel(item.type) }}</SyvoraBadge>
                            <span class="dash-cost-name">{{ item.name }}</span>
                            <span class="dash-cost-value">{{ formatCurrency(item.cost) }}</span>
                        </div>
                        <div class="dash-cost-track">
                            <div
                                class="dash-cost-fill"
                                :class="`dash-cost-fill--${item.type}`"
                                :style="{ width: barFill(item) }"
                            />
                        </div>
                    </RouterLink>
                </div>
            </SyvoraCard>

            <!-- Status distribution -->
            <SyvoraCard title="Status distribution">
                <div class="dash-status">
                    <StatusBar label="Certificates" :breakdown="certStatusBreakdown" />
                    <StatusBar label="Licenses" :breakdown="licenseStatusBreakdown" />
                </div>
            </SyvoraCard>
        </template>
    </div>
</template>

<style scoped>
.dash {
    max-width: 960px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: 1rem;
}

.dash-greeting h1 {
    font-size: 1.5rem;
    font-weight: 700;
    margin: 0;
    word-break: break-word;
}

.dash-org {
    font-size: 0.875rem;
    color: var(--color-text-muted);
    margin: 0.25rem 0 0;
}

.dash-loading {
    text-align: center;
    color: var(--color-text-muted);
    padding: 2rem 0;
}

.dash-link {
    color: var(--color-accent);
    text-decoration: none;
}

.dash-link:hover {
    text-decoration: underline;
}

/* ── Stat cards ── */

.dash-stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 1rem;
}

@media (max-width: 600px) {
    .dash-stats {
        grid-template-columns: 1fr;
    }
}

.dash-stat-link {
    text-decoration: none;
    color: inherit;
}

.dash-stat {
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
    padding: 1rem 1.25rem;
}

.dash-stat-label {
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-muted);
    font-weight: 600;
}

.dash-stat-value {
    font-size: 1.75rem;
    font-weight: 700;
    line-height: 1.1;
    color: var(--color-text);
    word-break: break-word;
}

.dash-stat-value--warn { color: var(--color-warning); }
.dash-stat-value--cost { font-size: 1.375rem; }

/* ── Sparkline (mini stacked bar) ── */

.dash-stat :deep(.spark) {
    display: flex;
    height: 6px;
    border-radius: 999px;
    overflow: hidden;
    background: rgba(0, 0, 0, 0.06);
    margin-top: 0.25rem;
}

.dash-stat :deep(.spark-seg) { height: 100%; }
.dash-stat :deep(.spark-seg--valid)    { background: var(--color-success); }
.dash-stat :deep(.spark-seg--expiring) { background: var(--color-warning); }
.dash-stat :deep(.spark-seg--expired)  { background: var(--color-error); }

/* ── Upcoming list ── */

.dash-padded {
    padding: 0 1.25rem 1rem;
}

.dash-upcoming {
    display: flex;
    flex-direction: column;
}

.dash-upcoming-row {
    display: grid;
    grid-template-columns: auto 1fr auto auto;
    align-items: center;
    gap: 0.75rem;
    padding: 0.625rem 1.25rem;
    text-decoration: none;
    color: inherit;
    border-top: 1px solid rgba(0, 0, 0, 0.04);
    transition: background 0.1s;
}

.dash-upcoming-row:first-child { border-top: none; }

.dash-upcoming-row:hover {
    background: rgba(0, 0, 0, 0.02);
}

.dash-upcoming-main {
    display: flex;
    flex-direction: column;
    gap: 0.125rem;
    min-width: 0;
}

.dash-upcoming-name {
    font-weight: 600;
    font-size: 0.875rem;
    word-break: break-word;
}

.dash-upcoming-meta {
    font-size: 0.75rem;
    color: var(--color-text-muted);
}

.dash-upcoming-date {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 0.125rem;
    font-size: 0.8125rem;
}

.dash-upcoming-days {
    font-size: 0.75rem;
    color: var(--color-text-muted);
}

@media (max-width: 600px) {
    .dash-upcoming-row {
        grid-template-columns: auto 1fr auto;
        grid-template-areas:
            "type name   status"
            "type date   date";
        padding: 0.75rem 1rem;
    }

    .dash-upcoming-row > :nth-child(1) { grid-area: type; }
    .dash-upcoming-main                { grid-area: name; }
    .dash-upcoming-date                { grid-area: date; align-items: flex-start; flex-direction: row; gap: 0.5rem; }
    .dash-upcoming-row > :nth-child(4) { grid-area: status; }
}

/* ── Cost breakdown ── */

.dash-cost {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    padding: 0 1.25rem 1rem;
}

.dash-cost-row {
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
    text-decoration: none;
    color: inherit;
    padding: 0.5rem 0;
    border-bottom: 1px solid rgba(0, 0, 0, 0.04);
}

.dash-cost-row:last-child { border-bottom: none; }

.dash-cost-header {
    display: flex;
    align-items: center;
    gap: 0.625rem;
    flex-wrap: wrap;
}

.dash-cost-name {
    flex: 1;
    min-width: 0;
    font-weight: 500;
    font-size: 0.875rem;
    word-break: break-word;
}

.dash-cost-value {
    font-size: 0.8125rem;
    font-weight: 600;
    color: var(--color-text);
    flex-shrink: 0;
}

.dash-cost-track {
    height: 8px;
    border-radius: 999px;
    background: rgba(0, 0, 0, 0.05);
    overflow: hidden;
}

.dash-cost-fill {
    height: 100%;
    border-radius: 999px;
    transition: width 0.3s ease;
}

.dash-cost-fill--license     { background: var(--color-accent); }
.dash-cost-fill--certificate { background: var(--color-accent-dim); }

/* ── Status distribution ── */

.dash-status {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    padding: 0 1.25rem 1.25rem;
}

.dash-status :deep(.statbar) {
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
}

.dash-status :deep(.statbar-label) {
    font-size: 0.8125rem;
    font-weight: 600;
    color: var(--color-text);
}

.dash-status :deep(.statbar-track) {
    display: flex;
    height: 14px;
    border-radius: 999px;
    overflow: hidden;
    background: rgba(0, 0, 0, 0.06);
}

.dash-status :deep(.statbar-track--empty) {
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.04);
    color: var(--color-text-muted);
    font-size: 0.75rem;
    font-style: italic;
}

.dash-status :deep(.statbar-seg)           { height: 100%; transition: width 0.3s ease; }
.dash-status :deep(.statbar-seg--valid)    { background: var(--color-success); }
.dash-status :deep(.statbar-seg--expiring) { background: var(--color-warning); }
.dash-status :deep(.statbar-seg--expired)  { background: var(--color-error); }

.dash-status :deep(.statbar-legend) {
    display: flex;
    gap: 0.375rem;
    flex-wrap: wrap;
    font-size: 0.75rem;
    color: var(--color-text-muted);
}

.dash-status :deep(.statbar-sep) {
    opacity: 0.5;
}

/* ── Extra-narrow (iPhone SE 1st gen) ── */

@media (max-width: 360px) {
    .dash-greeting h1 { font-size: 1.25rem; }
    .dash-stat-value { font-size: 1.5rem; }
    .dash-stat-value--cost { font-size: 1.125rem; }
}
</style>
