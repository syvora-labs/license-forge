import { ref, computed } from 'vue'
import { useCertificates } from './useCertificates'
import { useLicenses } from './useLicenses'

export type ItemStatus = 'valid' | 'expiring' | 'expired'
export type ItemType = 'certificate' | 'license'

export interface UpcomingItem {
    id: string
    type: ItemType
    name: string
    expires_at: string
    responsible: { email: string; display_name: string | null } | null
    cost: number | null
    status: ItemStatus
    href: string
}

export interface CostItem {
    id: string
    type: ItemType
    name: string
    cost: number
    href: string
}

export interface StatusBreakdown {
    valid: number
    expiring: number
    expired: number
    total: number
}

const loading = ref(false)

function daysUntil(dateStr: string): number {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const target = new Date(dateStr)
    target.setHours(0, 0, 0, 0)
    return Math.floor((target.getTime() - today.getTime()) / (1000 * 60 * 60 * 24))
}

function statusFor(expires_at: string): ItemStatus {
    const days = daysUntil(expires_at)
    if (days < 0) return 'expired'
    if (days <= 30) return 'expiring'
    return 'valid'
}

export function useDashboard() {
    const {
        certificates,
        summary: certSummary,
        fetchCertificates,
        fetchCertificateSummary,
    } = useCertificates()

    const {
        licenses,
        summary: licenseSummary,
        fetchLicenses,
        fetchLicenseSummary,
    } = useLicenses()

    const upcoming = computed<UpcomingItem[]>(() => {
        const items: UpcomingItem[] = []

        for (const c of certificates.value) {
            if (daysUntil(c.expires_at) > 60) continue
            items.push({
                id: c.id,
                type: 'certificate',
                name: c.name,
                expires_at: c.expires_at,
                responsible: c.responsible ?? null,
                cost: c.cost,
                status: statusFor(c.expires_at),
                href: `/certificates/${c.id}`,
            })
        }

        for (const l of licenses.value) {
            if (daysUntil(l.expires_at) > 60) continue
            items.push({
                id: l.id,
                type: 'license',
                name: l.name,
                expires_at: l.expires_at,
                responsible: l.responsible ?? null,
                cost: l.cost,
                status: statusFor(l.expires_at),
                href: `/licenses/${l.id}`,
            })
        }

        items.sort((a, b) => a.expires_at.localeCompare(b.expires_at))
        return items
    })

    const topByCost = computed<CostItem[]>(() => {
        const items: CostItem[] = []

        for (const c of certificates.value) {
            if (c.cost == null) continue
            items.push({
                id: c.id,
                type: 'certificate',
                name: c.name,
                cost: c.cost,
                href: `/certificates/${c.id}`,
            })
        }

        for (const l of licenses.value) {
            if (l.cost == null) continue
            items.push({
                id: l.id,
                type: 'license',
                name: l.name,
                cost: l.cost,
                href: `/licenses/${l.id}`,
            })
        }

        items.sort((a, b) => b.cost - a.cost)
        return items.slice(0, 10)
    })

    const totalCost = computed(() => {
        let sum = 0
        for (const c of certificates.value) sum += c.cost ?? 0
        for (const l of licenses.value) sum += l.cost ?? 0
        return sum
    })

    function breakdownFromSummary(
        s: { total_count: number; expiring_soon_count: number; expired_count: number } | null,
    ): StatusBreakdown {
        if (!s) return { valid: 0, expiring: 0, expired: 0, total: 0 }
        const valid = Math.max(0, s.total_count - s.expiring_soon_count - s.expired_count)
        return {
            valid,
            expiring: s.expiring_soon_count,
            expired: s.expired_count,
            total: s.total_count,
        }
    }

    const certStatusBreakdown = computed(() => breakdownFromSummary(certSummary.value))
    const licenseStatusBreakdown = computed(() => breakdownFromSummary(licenseSummary.value))

    async function refresh(mandatorId: string) {
        loading.value = true
        try {
            await Promise.all([
                fetchCertificates(mandatorId),
                fetchLicenses(mandatorId),
                fetchCertificateSummary(mandatorId),
                fetchLicenseSummary(mandatorId),
            ])
        } finally {
            loading.value = false
        }
    }

    return {
        loading,
        upcoming,
        topByCost,
        totalCost,
        certStatusBreakdown,
        licenseStatusBreakdown,
        refresh,
    }
}
