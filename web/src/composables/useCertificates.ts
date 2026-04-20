import { ref } from 'vue'
import { supabase } from '../lib/supabase'

export interface Certificate {
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

export interface CertificateForm {
    name: string
    expires_at: string
    responsible_user_id: string | null
    provider?: string | null
    cost?: number | null
    notes?: string | null
}

export interface CertificateSummary {
    total_count: number
    expiring_soon_count: number
    expired_count: number
}

const certificates = ref<Certificate[]>([])
const summary = ref<CertificateSummary | null>(null)
const loading = ref(false)

async function fetchCertificates(mandatorId: string) {
    loading.value = true
    try {
        const { data, error } = await supabase
            .from('certificates')
            .select('*, responsible:responsible_user_id(id, email, display_name)')
            .eq('mandator_id', mandatorId)
            .order('expires_at', { ascending: true })

        if (error) throw error
        certificates.value = (data ?? []) as Certificate[]
    } finally {
        loading.value = false
    }
}

async function fetchCertificateSummary(mandatorId: string) {
    const { data, error } = await supabase.rpc('get_certificate_summary', {
        p_mandator_id: mandatorId,
    })

    if (error) throw error
    summary.value = (Array.isArray(data) ? data[0] : data) as CertificateSummary
}

async function getCertificate(id: string): Promise<Certificate | null> {
    const { data, error } = await supabase
        .from('certificates')
        .select('*, responsible:responsible_user_id(id, email, display_name)')
        .eq('id', id)
        .single()

    if (error) throw error
    return data as Certificate | null
}

async function createCertificate(mandatorId: string, form: CertificateForm): Promise<Certificate> {
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
        .from('certificates')
        .insert(payload)
        .select()
        .single()

    if (error) throw error
    return data as Certificate
}

async function updateCertificate(id: string, form: Partial<CertificateForm>): Promise<Certificate> {
    const { data: { user } } = await supabase.auth.getUser()

    const payload: Record<string, unknown> = {
        ...form,
        updated_by: user?.id ?? null,
    }

    const { data, error } = await supabase
        .from('certificates')
        .update(payload)
        .eq('id', id)
        .select()
        .single()

    if (error) throw error
    return data as Certificate
}

async function deleteCertificate(id: string) {
    const { error } = await supabase
        .from('certificates')
        .delete()
        .eq('id', id)

    if (error) throw error
}

export function useCertificates() {
    return {
        certificates,
        summary,
        loading,
        fetchCertificates,
        fetchCertificateSummary,
        getCertificate,
        createCertificate,
        updateCertificate,
        deleteCertificate,
    }
}
