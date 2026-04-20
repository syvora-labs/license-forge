import { ref, computed, reactive } from 'vue'
import { supabase } from '../lib/supabase'

export interface Mandator {
    id: string
    name: string
    slug: string
    created_by: string | null
    updated_by: string | null
    created_at: string
    updated_at: string
    [key: string]: unknown // future module_* columns
}

export interface MandatorUser {
    mandator_id: string
    user_id: string
    role: 'admin' | 'member'
}

export interface ModuleDefinition {
    route: string
    column: string
    label: string
}

export interface MandatorMember {
    user_id: string
    role: 'admin' | 'member'
    email: string
    display_name: string | null
}

const mandator = ref<Mandator | null>(null)
const mandators = ref<Mandator[]>([])
const currentRole = ref<'admin' | 'member' | null>(null)
const members = ref<MandatorMember[]>([])
const loading = ref(false)

const MODULE_DEFINITIONS = reactive<ModuleDefinition[]>([])

const STORAGE_KEY = 'license-forge:mandator-id'

const enabledModules = computed<string[]>(() => {
    if (!mandator.value) return []
    return MODULE_DEFINITIONS
        .filter((m) => mandator.value![m.column] === true)
        .map((m) => m.route)
})

function isModuleEnabled(name: string): boolean {
    return enabledModules.value.includes(name)
}

const certificatesEnabled = computed(() => isModuleEnabled('certificates'))
const licensesEnabled = computed(() => isModuleEnabled('licenses'))

async function fetchMandators() {
    loading.value = true
    try {
        const { data: memberships, error: memberError } = await supabase
            .from('mandator_users')
            .select('mandator_id, role')

        if (memberError) throw memberError
        if (!memberships || memberships.length === 0) {
            mandators.value = []
            mandator.value = null
            currentRole.value = null
            return
        }

        const ids = memberships.map((m) => m.mandator_id)
        const { data, error } = await supabase
            .from('mandators')
            .select('*')
            .in('id', ids)

        if (error) throw error
        mandators.value = (data ?? []) as Mandator[]

        const savedId = localStorage.getItem(STORAGE_KEY)
        const saved = mandators.value.find((m) => m.id === savedId)
        const target = saved ?? mandators.value[0] ?? null

        if (target) {
            mandator.value = target
            const membership = memberships.find((m) => m.mandator_id === target.id)
            currentRole.value = (membership?.role as 'admin' | 'member') ?? null
            localStorage.setItem(STORAGE_KEY, target.id)
        } else {
            mandator.value = null
            currentRole.value = null
        }
    } finally {
        loading.value = false
    }
}

async function selectMandator(id: string) {
    const target = mandators.value.find((m) => m.id === id)
    if (!target) return

    mandator.value = target
    localStorage.setItem(STORAGE_KEY, id)

    const { data } = await supabase
        .from('mandator_users')
        .select('role')
        .eq('mandator_id', id)
        .single()

    currentRole.value = (data?.role as 'admin' | 'member') ?? null
}

async function fetchMandatorMembers(mandatorId: string) {
    const { data: memberRows, error } = await supabase
        .from('mandator_users')
        .select('user_id, role')
        .eq('mandator_id', mandatorId)

    if (error) throw error
    if (!memberRows || memberRows.length === 0) {
        members.value = []
        return
    }

    const userIds = memberRows.map((m) => m.user_id)
    const { data: profiles } = await supabase
        .from('profiles')
        .select('id, email, display_name')
        .in('id', userIds)

    const profileMap = Object.fromEntries(
        (profiles ?? []).map((p) => [p.id, p]),
    )

    members.value = memberRows.map((m) => ({
        user_id: m.user_id,
        role: m.role as 'admin' | 'member',
        email: profileMap[m.user_id]?.email ?? 'Unknown',
        display_name: profileMap[m.user_id]?.display_name ?? null,
    }))
}

async function refreshMandator() {
    if (!mandator.value) return

    const { data, error } = await supabase
        .from('mandators')
        .select('*')
        .eq('id', mandator.value.id)
        .single()

    if (!error && data) {
        mandator.value = data as Mandator
        const idx = mandators.value.findIndex((m) => m.id === data.id)
        if (idx !== -1) mandators.value[idx] = data as Mandator
    }
}

export function useMandator() {
    return {
        mandator,
        mandators,
        currentRole,
        members,
        loading,
        enabledModules,
        certificatesEnabled,
        licensesEnabled,
        MODULE_DEFINITIONS,
        isModuleEnabled,
        fetchMandators,
        fetchMandatorMembers,
        selectMandator,
        refreshMandator,
    }
}
