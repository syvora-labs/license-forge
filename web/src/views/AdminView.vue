<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import {
    SyvoraCard,
    SyvoraInput,
    SyvoraButton,
    SyvoraAlert,
    SyvoraFormField,
    SyvoraModal,
    SyvoraBadge,
    SyvoraEmptyState,
} from '@syvora/ui'
import { supabase } from '../lib/supabase'
import { useMandator, type Mandator } from '../composables/useMandator'

const { MODULE_DEFINITIONS, fetchMandators } = useMandator()

interface MandatorWithMembers extends Mandator {
    memberCount?: number
}

interface Member {
    id: string
    user_id: string
    role: 'admin' | 'member'
    email?: string
}

const allMandators = ref<MandatorWithMembers[]>([])
const loading = ref(false)
const error = ref('')

// Create / edit modal
const showModal = ref(false)
const editingId = ref<string | null>(null)
const formName = ref('')
const formSlug = ref('')
const formModules = ref<Record<string, boolean>>({})
const saving = ref(false)

// Member management
const expandedMandator = ref<string | null>(null)
const members = ref<Member[]>([])
const membersLoading = ref(false)
const inviteEmail = ref('')
const inviteRole = ref<'admin' | 'member'>('member')
const inviting = ref(false)

const modalTitle = computed(() => editingId.value ? 'Edit mandator' : 'Create mandator')

function slugify(text: string): string {
    return text
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-|-$/g, '')
}

async function fetchAllMandators() {
    loading.value = true
    try {
        const { data, error: err } = await supabase
            .from('mandators')
            .select('*')
            .order('name')

        if (err) throw err
        allMandators.value = (data ?? []) as MandatorWithMembers[]
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to load mandators'
    } finally {
        loading.value = false
    }
}

function openCreate() {
    editingId.value = null
    formName.value = ''
    formSlug.value = ''
    formModules.value = Object.fromEntries(
        MODULE_DEFINITIONS.map((m) => [m.column, true]),
    )
    showModal.value = true
}

function openEdit(mandator: MandatorWithMembers) {
    editingId.value = mandator.id
    formName.value = mandator.name
    formSlug.value = mandator.slug
    formModules.value = Object.fromEntries(
        MODULE_DEFINITIONS.map((m) => [m.column, mandator[m.column] === true]),
    )
    showModal.value = true
}

function onNameInput(val: string) {
    formName.value = val
    if (!editingId.value) {
        formSlug.value = slugify(val)
    }
}

async function handleSave() {
    saving.value = true
    error.value = ''
    try {
        const payload: Record<string, unknown> = {
            name: formName.value,
            slug: formSlug.value,
            ...formModules.value,
        }

        if (editingId.value) {
            const { error: err } = await supabase
                .from('mandators')
                .update(payload)
                .eq('id', editingId.value)
            if (err) throw err
        } else {
            const { error: err } = await supabase
                .from('mandators')
                .insert(payload)
            if (err) throw err
        }

        showModal.value = false
        await fetchAllMandators()
        await fetchMandators()
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to save mandator'
    } finally {
        saving.value = false
    }
}

async function toggleExpand(mandatorId: string) {
    if (expandedMandator.value === mandatorId) {
        expandedMandator.value = null
        return
    }
    expandedMandator.value = mandatorId
    await fetchMembers(mandatorId)
}

async function fetchMembers(mandatorId: string) {
    membersLoading.value = true
    try {
        const { data, error: err } = await supabase
            .from('mandator_users')
            .select('id, user_id, role')
            .eq('mandator_id', mandatorId)

        if (err) throw err

        const userIds = (data ?? []).map((m) => m.user_id)
        let profileMap: Record<string, string> = {}

        if (userIds.length > 0) {
            const { data: profiles } = await supabase
                .from('profiles')
                .select('id, email')
                .in('id', userIds)

            profileMap = Object.fromEntries(
                (profiles ?? []).map((p) => [p.id, p.email]),
            )
        }

        members.value = (data ?? []).map((m) => ({
            ...m,
            email: profileMap[m.user_id] ?? 'Unknown',
        })) as Member[]
    } finally {
        membersLoading.value = false
    }
}

async function updateMemberRole(member: Member, newRole: 'admin' | 'member') {
    const { error: err } = await supabase
        .from('mandator_users')
        .update({ role: newRole })
        .eq('id', member.id)

    if (err) {
        error.value = err.message
        return
    }
    member.role = newRole
}

async function removeMember(member: Member) {
    if (!confirm(`Remove ${member.email} from this mandator?`)) return

    const { error: err } = await supabase
        .from('mandator_users')
        .delete()
        .eq('id', member.id)

    if (err) {
        error.value = err.message
        return
    }
    members.value = members.value.filter((m) => m.id !== member.id)
}

async function inviteMember() {
    if (!expandedMandator.value || !inviteEmail.value) return
    inviting.value = true
    error.value = ''

    try {
        // Look up user by email
        const { data: profile } = await supabase
            .from('profiles')
            .select('id')
            .eq('email', inviteEmail.value)
            .single()

        if (!profile) {
            error.value = 'No user found with that email'
            return
        }

        const { error: err } = await supabase
            .from('mandator_users')
            .insert({
                mandator_id: expandedMandator.value,
                user_id: profile.id,
                role: inviteRole.value,
            })

        if (err) throw err

        inviteEmail.value = ''
        await fetchMembers(expandedMandator.value)
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to invite member'
    } finally {
        inviting.value = false
    }
}

function getModuleBadges(mandator: MandatorWithMembers) {
    return MODULE_DEFINITIONS.map((m) => ({
        label: m.label,
        enabled: mandator[m.column] === true,
    }))
}

onMounted(fetchAllMandators)
</script>

<template>
    <div class="admin">
        <div class="admin-header">
            <h1>Administration</h1>
            <SyvoraButton @click="openCreate">Create mandator</SyvoraButton>
        </div>

        <SyvoraAlert v-if="error" variant="error" dismissible @dismiss="error = ''">
            {{ error }}
        </SyvoraAlert>

        <div v-if="loading" class="admin-loading">Loading...</div>

        <SyvoraEmptyState v-else-if="allMandators.length === 0">
            No mandators yet. Create one to get started.
        </SyvoraEmptyState>

        <div v-else class="admin-list">
            <SyvoraCard v-for="m in allMandators" :key="m.id">
                <template #header>
                    <div class="mandator-header">
                        <div>
                            <h3 class="mandator-name">{{ m.name }}</h3>
                            <span class="mandator-slug">{{ m.slug }}</span>
                        </div>
                        <div class="mandator-actions">
                            <div v-if="getModuleBadges(m).length" class="mandator-badges">
                                <SyvoraBadge
                                    v-for="b in getModuleBadges(m)"
                                    :key="b.label"
                                    :variant="b.enabled ? 'success' : 'muted'"
                                >
                                    {{ b.label }}
                                </SyvoraBadge>
                            </div>
                            <SyvoraButton size="sm" variant="ghost" @click="openEdit(m)">Edit</SyvoraButton>
                            <SyvoraButton size="sm" variant="ghost" @click="toggleExpand(m.id)">
                                {{ expandedMandator === m.id ? 'Hide members' : 'Members' }}
                            </SyvoraButton>
                        </div>
                    </div>
                </template>

                <div v-if="expandedMandator === m.id" class="members-section">
                    <div v-if="membersLoading" class="admin-loading">Loading members...</div>

                    <template v-else>
                        <div v-if="members.length === 0" class="members-empty">No members yet.</div>

                        <div v-for="member in members" :key="member.id" class="member-row">
                            <span class="member-email">{{ member.email }}</span>
                            <SyvoraBadge :variant="member.role === 'admin' ? 'warning' : 'muted'">
                                {{ member.role }}
                            </SyvoraBadge>
                            <SyvoraButton
                                size="sm"
                                variant="ghost"
                                @click="updateMemberRole(member, member.role === 'admin' ? 'member' : 'admin')"
                            >
                                {{ member.role === 'admin' ? 'Demote' : 'Promote' }}
                            </SyvoraButton>
                            <SyvoraButton size="sm" variant="ghost" @click="removeMember(member)">
                                Remove
                            </SyvoraButton>
                        </div>

                        <div class="invite-row">
                            <SyvoraInput
                                v-model="inviteEmail"
                                placeholder="Email address"
                                type="email"
                            />
                            <select v-model="inviteRole" class="role-select">
                                <option value="member">Member</option>
                                <option value="admin">Admin</option>
                            </select>
                            <SyvoraButton
                                size="sm"
                                :loading="inviting"
                                :disabled="!inviteEmail"
                                @click="inviteMember"
                            >
                                Invite
                            </SyvoraButton>
                        </div>
                    </template>
                </div>
            </SyvoraCard>
        </div>

        <!-- Create / Edit modal -->
        <SyvoraModal
            v-if="showModal"
            :title="modalTitle"
            @close="showModal = false"
        >
            <SyvoraFormField label="Name" for="mandator-name">
                <SyvoraInput
                    id="mandator-name"
                    :model-value="formName"
                    placeholder="Organisation name"
                    @update:model-value="onNameInput"
                />
            </SyvoraFormField>

            <SyvoraFormField label="Slug" for="mandator-slug">
                <SyvoraInput
                    id="mandator-slug"
                    v-model="formSlug"
                    placeholder="organisation-slug"
                />
            </SyvoraFormField>

            <div v-if="MODULE_DEFINITIONS.length" class="module-toggles">
                <label
                    v-for="mod in MODULE_DEFINITIONS"
                    :key="mod.column"
                    class="module-toggle"
                >
                    <input
                        type="checkbox"
                        v-model="formModules[mod.column]"
                    />
                    {{ mod.label }}
                </label>
            </div>

            <template #footer>
                <SyvoraButton variant="ghost" @click="showModal = false">Cancel</SyvoraButton>
                <SyvoraButton :loading="saving" :disabled="!formName || !formSlug" @click="handleSave">
                    Save
                </SyvoraButton>
            </template>
        </SyvoraModal>
    </div>
</template>

<style scoped>
.admin {
    max-width: 960px;
    margin: 0 auto;
}

.admin-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    margin-bottom: 1.5rem;
    flex-wrap: wrap;
}

.admin-header h1 {
    font-size: 1.5rem;
    font-weight: 700;
    margin: 0;
}

.admin-loading {
    text-align: center;
    color: var(--color-text-muted);
    padding: 2rem 0;
}

.admin-list {
    display: flex;
    flex-direction: column;
    gap: 1rem;
}

.mandator-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.25rem;
    gap: 1rem;
    flex-wrap: wrap;
}

@media (max-width: 600px) {
    .mandator-header {
        flex-direction: column;
        align-items: flex-start;
    }

    .mandator-actions {
        width: 100%;
        flex-wrap: wrap;
    }

    .mandator-badges {
        flex-wrap: wrap;
    }
}

.mandator-name {
    font-size: 1rem;
    font-weight: 700;
    margin: 0;
}

.mandator-slug {
    font-size: 0.75rem;
    color: var(--color-text-muted);
}

.mandator-actions {
    display: flex;
    align-items: center;
    gap: 0.5rem;
}

.mandator-badges {
    display: flex;
    gap: 0.375rem;
}

.members-section {
    padding: 0.5rem 0;
}

.members-empty {
    font-size: 0.875rem;
    color: var(--color-text-muted);
    padding: 0.5rem 0;
}

.member-row {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.5rem 0;
    border-bottom: 1px solid rgba(0, 0, 0, 0.04);
    flex-wrap: wrap;
}

.member-email {
    flex: 1;
    min-width: 160px;
    font-size: 0.875rem;
    word-break: break-all;
}

.invite-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding-top: 0.75rem;
    flex-wrap: wrap;
}

.invite-row .syvora-input-wrap {
    flex: 1;
    min-width: 180px;
}

@media (max-width: 600px) {
    .member-row {
        gap: 0.5rem;
    }
}

.role-select {
    padding: 0.5rem;
    border: 1px solid rgba(0, 0, 0, 0.1);
    border-radius: var(--radius-sm, 0.625rem);
    background: #fff;
    font-size: 0.875rem;
    color: var(--color-text);
}

.module-toggles {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
}

.module-toggle {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.875rem;
    cursor: pointer;
}

.module-toggle input[type="checkbox"] {
    accent-color: var(--color-accent);
}
</style>
