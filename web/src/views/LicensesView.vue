<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import {
    SyvoraCard,
    SyvoraButton,
    SyvoraBadge,
    SyvoraModal,
    SyvoraInput,
    SyvoraFormField,
    SyvoraEmptyState,
    SyvoraAlert,
    useIsMobile,
} from '@syvora/ui'
import { useMandator } from '../composables/useMandator'
import { useLicenses, type License } from '../composables/useLicenses'

const isMobile = useIsMobile()

const { mandator, members, fetchMandatorMembers } = useMandator()
const {
    licenses,
    summary,
    loading,
    fetchLicenses,
    fetchLicenseSummary,
    createLicense,
} = useLicenses()

const showModal = ref(false)
const saving = ref(false)
const error = ref('')

const formName = ref('')
const formExpiresAt = ref('')
const formResponsibleUserId = ref<string | null>(null)

async function loadAll() {
    if (!mandator.value) return
    await Promise.all([
        fetchLicenses(mandator.value.id),
        fetchLicenseSummary(mandator.value.id),
        fetchMandatorMembers(mandator.value.id),
    ])
}

onMounted(loadAll)
watch(() => mandator.value?.id, loadAll)

function openCreate() {
    formName.value = ''
    formExpiresAt.value = ''
    formResponsibleUserId.value = null
    error.value = ''
    showModal.value = true
}

async function handleCreate() {
    if (!mandator.value) return
    saving.value = true
    error.value = ''
    try {
        await createLicense(mandator.value.id, {
            name: formName.value,
            expires_at: formExpiresAt.value,
            responsible_user_id: formResponsibleUserId.value,
        })
        showModal.value = false
        await Promise.all([
            fetchLicenses(mandator.value.id),
            fetchLicenseSummary(mandator.value.id),
        ])
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to create license'
    } finally {
        saving.value = false
    }
}

function daysUntil(dateStr: string): number {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const target = new Date(dateStr)
    target.setHours(0, 0, 0, 0)
    return Math.floor((target.getTime() - today.getTime()) / (1000 * 60 * 60 * 24))
}

function statusFor(lic: License): { label: string; variant: 'success' | 'warning' | 'error' } {
    const days = daysUntil(lic.expires_at)
    if (days < 0) return { label: 'Expired', variant: 'error' }
    if (days <= 7) return { label: 'Expiring', variant: 'warning' }
    return { label: 'Valid', variant: 'success' }
}

function formatDate(dateStr: string): string {
    return new Date(dateStr).toLocaleDateString(undefined, {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
    })
}

function responsibleLabel(lic: License): string {
    if (!lic.responsible) return '—'
    return lic.responsible.display_name || lic.responsible.email
}

const hasLicenses = computed(() => licenses.value.length > 0)
</script>

<template>
    <div class="lics">
        <header class="lics-header">
            <div>
                <h1>Licenses</h1>
                <div v-if="summary" class="lics-pills">
                    <SyvoraBadge>Total: {{ summary.total_count }}</SyvoraBadge>
                    <SyvoraBadge variant="warning">Expiring: {{ summary.expiring_soon_count }}</SyvoraBadge>
                    <SyvoraBadge variant="error">Expired: {{ summary.expired_count }}</SyvoraBadge>
                </div>
            </div>
            <SyvoraButton :full="isMobile" @click="openCreate">Add license</SyvoraButton>
        </header>

        <div v-if="loading" class="lics-loading">Loading...</div>

        <SyvoraEmptyState v-else-if="!hasLicenses">
            No licenses yet. Add one to start tracking renewal dates.
        </SyvoraEmptyState>

        <!-- Desktop: table -->
        <SyvoraCard v-else-if="!isMobile">
            <table class="lics-table">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Expires</th>
                        <th>Responsible</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    <tr v-for="lic in licenses" :key="lic.id">
                        <td>
                            <RouterLink :to="`/licenses/${lic.id}`" class="lics-name-link">
                                {{ lic.name }}
                            </RouterLink>
                        </td>
                        <td>{{ formatDate(lic.expires_at) }}</td>
                        <td>{{ responsibleLabel(lic) }}</td>
                        <td>
                            <SyvoraBadge :variant="statusFor(lic).variant">
                                {{ statusFor(lic).label }}
                            </SyvoraBadge>
                        </td>
                    </tr>
                </tbody>
            </table>
        </SyvoraCard>

        <!-- Mobile: card list -->
        <div v-else class="lics-cards">
            <RouterLink
                v-for="lic in licenses"
                :key="lic.id"
                :to="`/licenses/${lic.id}`"
                class="lics-card-link"
            >
                <SyvoraCard>
                    <div class="lics-card">
                        <div class="lics-card-top">
                            <span class="lics-card-name">{{ lic.name }}</span>
                            <SyvoraBadge :variant="statusFor(lic).variant">
                                {{ statusFor(lic).label }}
                            </SyvoraBadge>
                        </div>
                        <div class="lics-card-row">
                            <span class="lics-card-label">Expires</span>
                            <span>{{ formatDate(lic.expires_at) }}</span>
                        </div>
                        <div class="lics-card-row">
                            <span class="lics-card-label">Responsible</span>
                            <span>{{ responsibleLabel(lic) }}</span>
                        </div>
                    </div>
                </SyvoraCard>
            </RouterLink>
        </div>

        <SyvoraModal v-if="showModal" title="Add license" @close="showModal = false">
            <SyvoraAlert v-if="error" variant="error" dismissible @dismiss="error = ''">
                {{ error }}
            </SyvoraAlert>

            <SyvoraFormField label="Name" for="lic-name">
                <SyvoraInput
                    id="lic-name"
                    v-model="formName"
                    placeholder="e.g. JetBrains All Products Pack"
                />
            </SyvoraFormField>

            <SyvoraFormField label="Expiration date" for="lic-expires">
                <SyvoraInput
                    id="lic-expires"
                    v-model="formExpiresAt"
                    type="date"
                />
            </SyvoraFormField>

            <SyvoraFormField label="Responsible (optional)" for="lic-responsible">
                <select
                    id="lic-responsible"
                    v-model="formResponsibleUserId"
                    class="lics-select"
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

            <template #footer>
                <SyvoraButton variant="ghost" @click="showModal = false">Cancel</SyvoraButton>
                <SyvoraButton
                    :loading="saving"
                    :disabled="!formName || !formExpiresAt"
                    @click="handleCreate"
                >
                    Add
                </SyvoraButton>
            </template>
        </SyvoraModal>
    </div>
</template>

<style scoped>
.lics {
    max-width: 960px;
    margin: 0 auto;
}

.lics-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 1rem;
    margin-bottom: 1.5rem;
}

@media (max-width: 600px) {
    .lics-header {
        flex-direction: column;
        align-items: stretch;
    }
}

@media (max-width: 360px) {
    .lics-header h1 {
        font-size: 1.25rem;
    }

    .lics-card {
        padding: 0.75rem;
    }

    .lics-card-name {
        font-size: 0.875rem;
    }

    .lics-pills :deep(.badge) {
        font-size: 0.6875rem;
    }
}

.lics-cards {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
}

.lics-card-link {
    text-decoration: none;
    color: inherit;
}

.lics-card {
    display: flex;
    flex-direction: column;
    gap: 0.625rem;
    padding: 0.875rem 1rem;
}

.lics-card-top {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 0.5rem;
    flex-wrap: wrap;
}

.lics-card-name {
    font-weight: 600;
    font-size: 0.9375rem;
    color: var(--color-text);
    flex: 1;
    min-width: 0;
    word-break: break-word;
    overflow-wrap: anywhere;
}

.lics-card-top :deep(.badge) {
    flex-shrink: 0;
}

.lics-card-row {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 0.75rem;
    font-size: 0.8125rem;
    color: var(--color-text);
}

.lics-card-label {
    color: var(--color-text-muted);
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-weight: 600;
    flex-shrink: 0;
}

.lics-card-row > span:last-child {
    text-align: right;
    min-width: 0;
    word-break: break-word;
    overflow-wrap: anywhere;
}

.lics-header h1 {
    font-size: 1.5rem;
    font-weight: 700;
    margin: 0 0 0.5rem;
}

.lics-pills {
    display: flex;
    gap: 0.375rem;
    flex-wrap: wrap;
}

.lics-loading {
    text-align: center;
    color: var(--color-text-muted);
    padding: 2rem 0;
}

.lics-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.875rem;
}

.lics-table th {
    text-align: left;
    padding: 0.625rem 0.75rem;
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-muted);
    border-bottom: 1px solid rgba(0, 0, 0, 0.08);
}

.lics-table td {
    padding: 0.75rem;
    border-bottom: 1px solid rgba(0, 0, 0, 0.04);
}

.lics-table tr:last-child td {
    border-bottom: none;
}

.lics-name-link {
    color: var(--color-text);
    text-decoration: none;
    font-weight: 500;
}

.lics-name-link:hover {
    color: var(--color-accent);
    text-decoration: underline;
}

.lics-select {
    width: 100%;
    padding: 0.75rem 1rem;
    background: rgba(255, 255, 255, 0.58);
    border: 1px solid rgba(255, 255, 255, 0.52);
    border-radius: var(--radius-sm, 0.625rem);
    color: var(--color-text);
    font-size: 1rem;
    font-family: inherit;
}
</style>
