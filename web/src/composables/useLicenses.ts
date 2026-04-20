import { ref } from 'vue'
import { supabase } from '../lib/supabase'

export interface License {
    id: string
    mandator_id: string
    name: string
    expires_at: string
    responsible_user_id: string | null
    provider: string | null
    cost: number | null
    notes: string | null
    created_by: string | null
    updated_by: string | null
    created_at: string
    updated_at: string
    responsible?: { id: string; email: string; display_name: string | null } | null
}

export interface LicenseForm {
    name: string
    expires_at: string
    responsible_user_id: string | null
    provider?: string | null
    cost?: number | null
    notes?: string | null
}

export interface LicenseSummary {
    total_count: number
    expiring_soon_count: number
    expired_count: number
}

const licenses = ref<License[]>([])
const summary = ref<LicenseSummary | null>(null)
const loading = ref(false)

async function fetchLicenses(mandatorId: string) {
    loading.value = true
    try {
        const { data, error } = await supabase
            .from('licenses')
            .select('*, responsible:responsible_user_id(id, email, display_name)')
            .eq('mandator_id', mandatorId)
            .order('expires_at', { ascending: true })

        if (error) throw error
        licenses.value = (data ?? []) as License[]
    } finally {
        loading.value = false
    }
}

async function fetchLicenseSummary(mandatorId: string) {
    const { data, error } = await supabase.rpc('get_license_summary', {
        p_mandator_id: mandatorId,
    })

    if (error) throw error
    summary.value = (Array.isArray(data) ? data[0] : data) as LicenseSummary
}

async function getLicense(id: string): Promise<License | null> {
    const { data, error } = await supabase
        .from('licenses')
        .select('*, responsible:responsible_user_id(id, email, display_name)')
        .eq('id', id)
        .single()

    if (error) throw error
    return data as License | null
}

async function createLicense(mandatorId: string, form: LicenseForm): Promise<License> {
    const { data: { user } } = await supabase.auth.getUser()

    const payload = {
        mandator_id: mandatorId,
        name: form.name,
        expires_at: form.expires_at,
        responsible_user_id: form.responsible_user_id,
        provider: form.provider ?? null,
        cost: form.cost ?? null,
        notes: form.notes ?? null,
        created_by: user?.id ?? null,
        updated_by: user?.id ?? null,
    }

    const { data, error } = await supabase
        .from('licenses')
        .insert(payload)
        .select()
        .single()

    if (error) throw error
    return data as License
}

async function updateLicense(id: string, form: Partial<LicenseForm>): Promise<License> {
    const { data: { user } } = await supabase.auth.getUser()

    const payload: Record<string, unknown> = {
        ...form,
        updated_by: user?.id ?? null,
    }

    const { data, error } = await supabase
        .from('licenses')
        .update(payload)
        .eq('id', id)
        .select()
        .single()

    if (error) throw error
    return data as License
}

async function deleteLicense(id: string) {
    const { error } = await supabase
        .from('licenses')
        .delete()
        .eq('id', id)

    if (error) throw error
}

export function useLicenses() {
    return {
        licenses,
        summary,
        loading,
        fetchLicenses,
        fetchLicenseSummary,
        getLicense,
        createLicense,
        updateLicense,
        deleteLicense,
    }
}
