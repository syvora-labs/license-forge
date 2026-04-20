<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
    SyvoraCard,
    SyvoraButton,
    SyvoraBadge,
    SyvoraInput,
    SyvoraTextarea,
    SyvoraFormField,
    SyvoraAlert,
} from '@syvora/ui'
import { useMandator } from '../composables/useMandator'
import { useLicenses, type License } from '../composables/useLicenses'

const route = useRoute()
const router = useRouter()

const { mandator, members, fetchMandatorMembers } = useMandator()
const { getLicense, updateLicense, deleteLicense } = useLicenses()

const lic = ref<License | null>(null)
const loading = ref(true)
const saving = ref(false)
const deleting = ref(false)
const error = ref('')
const success = ref(false)

const formName = ref('')
const formExpiresAt = ref('')
const formResponsibleUserId = ref<string | null>(null)
const formProvider = ref('')
const formCost = ref<string>('')
const formNotes = ref('')

const licId = computed(() => route.params.id as string)

async function load() {
    loading.value = true
    error.value = ''
    try {
        const data = await getLicense(licId.value)
        if (!data) {
            error.value = 'License not found'
            return
        }
        lic.value = data
        formName.value = data.name
        formExpiresAt.value = data.expires_at
        formResponsibleUserId.value = data.responsible_user_id
        formProvider.value = data.provider ?? ''
        formCost.value = data.cost != null ? String(data.cost) : ''
        formNotes.value = data.notes ?? ''

        if (mandator.value) {
            await fetchMandatorMembers(mandator.value.id)
        }
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to load license'
    } finally {
        loading.value = false
    }
}

onMounted(load)
watch(licId, load)

async function handleSave() {
    if (!lic.value) return
    saving.value = true
    error.value = ''
    success.value = false
    try {
        const updated = await updateLicense(lic.value.id, {
            name: formName.value,
            expires_at: formExpiresAt.value,
            responsible_user_id: formResponsibleUserId.value,
            provider: formProvider.value || null,
            cost: formCost.value === '' ? null : Number(formCost.value),
            notes: formNotes.value || null,
        })
        lic.value = { ...lic.value, ...updated }
        success.value = true
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to save'
    } finally {
        saving.value = false
    }
}

async function handleDelete() {
    if (!lic.value) return
    if (!confirm(`Delete license "${lic.value.name}"? This cannot be undone.`)) return

    deleting.value = true
    try {
        await deleteLicense(lic.value.id)
        router.push('/licenses')
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to delete'
        deleting.value = false
    }
}

function daysUntil(dateStr: string): number {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const target = new Date(dateStr)
    target.setHours(0, 0, 0, 0)
    return Math.floor((target.getTime() - today.getTime()) / (1000 * 60 * 60 * 24))
}

const status = computed<{ label: string; variant: 'success' | 'warning' | 'error' } | null>(() => {
    if (!lic.value) return null
    const days = daysUntil(lic.value.expires_at)
    if (days < 0) return { label: 'Expired', variant: 'error' }
    if (days <= 7) return { label: 'Expiring', variant: 'warning' }
    return { label: 'Valid', variant: 'success' }
})

const daysLabel = computed(() => {
    if (!lic.value) return ''
    const days = daysUntil(lic.value.expires_at)
    if (days < 0) return `${Math.abs(days)} day${Math.abs(days) === 1 ? '' : 's'} overdue`
    if (days === 0) return 'Expires today'
    return `${days} day${days === 1 ? '' : 's'} until expiration`
})

function formatDateTime(dateStr: string): string {
    return new Date(dateStr).toLocaleString(undefined, {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
    })
}
</script>

<template>
    <div class="lic-detail">
        <RouterLink to="/licenses" class="lic-back">&larr; Back to licenses</RouterLink>

        <div v-if="loading" class="lic-loading">Loading...</div>

        <template v-else-if="lic">
            <header class="lic-header">
                <h1>{{ lic.name }}</h1>
                <SyvoraBadge v-if="status" :variant="status.variant">{{ status.label }}</SyvoraBadge>
            </header>

            <SyvoraAlert v-if="success" variant="info" dismissible @dismiss="success = false">
                License updated.
            </SyvoraAlert>

            <SyvoraAlert v-if="error" variant="error" dismissible @dismiss="error = ''">
                {{ error }}
            </SyvoraAlert>

            <div class="lic-grid">
                <SyvoraCard title="Basics">
                    <div class="lic-form">
                        <SyvoraFormField label="Name" for="l-name">
                            <SyvoraInput id="l-name" v-model="formName" />
                        </SyvoraFormField>

                        <SyvoraFormField label="Expiration date" for="l-expires">
                            <SyvoraInput id="l-expires" v-model="formExpiresAt" type="date" />
                        </SyvoraFormField>

                        <SyvoraFormField label="Responsible" for="l-responsible">
                            <select
                                id="l-responsible"
                                v-model="formResponsibleUserId"
                                class="lic-select"
                            >
                                <option :value="null">— None —</option>
                                <option
                                    v-for="m in members"
                                    :key="m.user_id"
                                    :value="m.user_id"
                                >
                                    {{ m.display_name || m.email }}
                                </option>
                            </select>
                        </SyvoraFormField>
                    </div>
                </SyvoraCard>

                <SyvoraCard title="Additional details">
                    <div class="lic-form">
                        <SyvoraFormField label="Provider" for="l-provider">
                            <SyvoraInput
                                id="l-provider"
                                v-model="formProvider"
                                placeholder="Vendor, e.g. Microsoft"
                            />
                        </SyvoraFormField>

                        <SyvoraFormField label="Cost" for="l-cost">
                            <SyvoraInput
                                id="l-cost"
                                v-model="formCost"
                                type="number"
                                suffix="CHF"
                                placeholder="0.00"
                            />
                        </SyvoraFormField>

                        <SyvoraFormField
                            label="Notes"
                            for="l-notes"
                            :char-count="formNotes.length"
                            :max-chars="2000"
                        >
                            <SyvoraTextarea
                                id="l-notes"
                                v-model="formNotes"
                                :rows="5"
                                :maxlength="2000"
                            />
                        </SyvoraFormField>
                    </div>
                </SyvoraCard>

                <SyvoraCard title="Status">
                    <div class="lic-status-panel">
                        <div class="lic-stat">
                            <span class="lic-stat-label">Expires</span>
                            <span class="lic-stat-value">{{ daysLabel }}</span>
                        </div>
                        <div class="lic-stat">
                            <span class="lic-stat-label">Last updated</span>
                            <span class="lic-stat-value">{{ formatDateTime(lic.updated_at) }}</span>
                        </div>
                    </div>
                </SyvoraCard>
            </div>

            <div class="lic-actions">
                <SyvoraButton
                    variant="ghost"
                    :loading="deleting"
                    @click="handleDelete"
                >
                    Delete
                </SyvoraButton>
                <SyvoraButton
                    :loading="saving"
                    :disabled="!formName || !formExpiresAt"
                    @click="handleSave"
                >
                    Save
                </SyvoraButton>
            </div>
        </template>
    </div>
</template>

<style scoped>
.lic-detail {
    max-width: 960px;
    margin: 0 auto;
}

.lic-back {
    display: inline-block;
    font-size: 0.8125rem;
    color: var(--color-text-muted);
    text-decoration: none;
    margin-bottom: 1rem;
}

.lic-back:hover {
    color: var(--color-accent);
}

.lic-header {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    margin-bottom: 1rem;
}

.lic-header h1 {
    font-size: 1.5rem;
    font-weight: 700;
    margin: 0;
    min-width: 0;
    word-break: break-word;
}

.lic-loading {
    text-align: center;
    color: var(--color-text-muted);
    padding: 2rem 0;
}

.lic-grid {
    display: grid;
    grid-template-columns: 1fr;
    gap: 1rem;
    margin: 1rem 0;
}

@media (min-width: 768px) {
    .lic-grid {
        grid-template-columns: 1fr 1fr;
    }

    .lic-grid > :deep(.card):nth-child(3) {
        grid-column: span 2;
    }
}

.lic-form {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    padding: 0 1.25rem 1.25rem;
}

.lic-select {
    width: 100%;
    padding: 0.75rem 1rem;
    background: rgba(255, 255, 255, 0.58);
    border: 1px solid rgba(255, 255, 255, 0.52);
    border-radius: var(--radius-sm, 0.625rem);
    color: var(--color-text);
    font-size: 1rem;
    font-family: inherit;
}

.lic-status-panel {
    padding: 0 1.25rem 1.25rem;
    display: flex;
    gap: 2rem;
    flex-wrap: wrap;
}

.lic-stat {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
}

.lic-stat-label {
    font-size: 0.75rem;
    color: var(--color-text-muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-weight: 600;
}

.lic-stat-value {
    font-size: 0.9375rem;
    font-weight: 500;
}

.lic-actions {
    display: flex;
    justify-content: space-between;
    gap: 0.75rem;
    margin-top: 1rem;
}

@media (max-width: 600px) {
    .lic-header {
        flex-direction: column;
        align-items: flex-start;
    }

    .lic-status-panel {
        gap: 1rem;
    }

    .lic-actions {
        flex-direction: column-reverse;
    }

    .lic-actions :deep(.btn) {
        width: 100%;
    }
}
</style>
