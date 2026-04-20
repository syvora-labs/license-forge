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
import { useCertificates, type Certificate } from '../composables/useCertificates'

const isMobile = useIsMobile()

const { mandator, members, fetchMandatorMembers } = useMandator()
const {
    certificates,
    summary,
    loading,
    fetchCertificates,
    fetchCertificateSummary,
    createCertificate,
} = useCertificates()

const showModal = ref(false)
const saving = ref(false)
const error = ref('')

const formName = ref('')
const formExpiresAt = ref('')
const formResponsibleUserId = ref<string | null>(null)

async function loadAll() {
    if (!mandator.value) return
    await Promise.all([
        fetchCertificates(mandator.value.id),
        fetchCertificateSummary(mandator.value.id),
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
        await createCertificate(mandator.value.id, {
            name: formName.value,
            expires_at: formExpiresAt.value,
            responsible_user_id: formResponsibleUserId.value,
        })
        showModal.value = false
        await Promise.all([
            fetchCertificates(mandator.value.id),
            fetchCertificateSummary(mandator.value.id),
        ])
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to create certificate'
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

function statusFor(cert: Certificate): { label: string; variant: 'success' | 'warning' | 'error' } {
    const days = daysUntil(cert.expires_at)
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

function responsibleLabel(cert: Certificate): string {
    if (!cert.responsible) return '—'
    return cert.responsible.display_name || cert.responsible.email
}

const hasCertificates = computed(() => certificates.value.length > 0)
</script>

<template>
    <div class="certs">
        <header class="certs-header">
            <div>
                <h1>Certificates</h1>
                <div v-if="summary" class="certs-pills">
                    <SyvoraBadge>Total: {{ summary.total_count }}</SyvoraBadge>
                    <SyvoraBadge variant="warning">Expiring: {{ summary.expiring_soon_count }}</SyvoraBadge>
                    <SyvoraBadge variant="error">Expired: {{ summary.expired_count }}</SyvoraBadge>
                </div>
            </div>
            <SyvoraButton :full="isMobile" @click="openCreate">Add certificate</SyvoraButton>
        </header>

        <div v-if="loading" class="certs-loading">Loading...</div>

        <SyvoraEmptyState v-else-if="!hasCertificates">
            No certificates yet. Add one to start tracking renewal dates.
        </SyvoraEmptyState>

        <!-- Desktop: table -->
        <SyvoraCard v-else-if="!isMobile">
            <table class="certs-table">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Expires</th>
                        <th>Responsible</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    <tr v-for="cert in certificates" :key="cert.id">
                        <td>
                            <RouterLink :to="`/certificates/${cert.id}`" class="certs-name-link">
                                {{ cert.name }}
                            </RouterLink>
                        </td>
                        <td>{{ formatDate(cert.expires_at) }}</td>
                        <td>{{ responsibleLabel(cert) }}</td>
                        <td>
                            <SyvoraBadge :variant="statusFor(cert).variant">
                                {{ statusFor(cert).label }}
                            </SyvoraBadge>
                        </td>
                    </tr>
                </tbody>
            </table>
        </SyvoraCard>

        <!-- Mobile: card list -->
        <div v-else class="certs-cards">
            <RouterLink
                v-for="cert in certificates"
                :key="cert.id"
                :to="`/certificates/${cert.id}`"
                class="certs-card-link"
            >
                <SyvoraCard>
                    <div class="certs-card">
                        <div class="certs-card-top">
                            <span class="certs-card-name">{{ cert.name }}</span>
                            <SyvoraBadge :variant="statusFor(cert).variant">
                                {{ statusFor(cert).label }}
                            </SyvoraBadge>
                        </div>
                        <div class="certs-card-row">
                            <span class="certs-card-label">Expires</span>
                            <span>{{ formatDate(cert.expires_at) }}</span>
                        </div>
                        <div class="certs-card-row">
                            <span class="certs-card-label">Responsible</span>
                            <span>{{ responsibleLabel(cert) }}</span>
                        </div>
                    </div>
                </SyvoraCard>
            </RouterLink>
        </div>

        <SyvoraModal v-if="showModal" title="Add certificate" @close="showModal = false">
            <SyvoraAlert v-if="error" variant="error" dismissible @dismiss="error = ''">
                {{ error }}
            </SyvoraAlert>

            <SyvoraFormField label="Name" for="cert-name">
                <SyvoraInput
                    id="cert-name"
                    v-model="formName"
                    placeholder="e.g. SSL — api.example.com"
                />
            </SyvoraFormField>

            <SyvoraFormField label="Expiration date" for="cert-expires">
                <SyvoraInput
                    id="cert-expires"
                    v-model="formExpiresAt"
                    type="date"
                />
            </SyvoraFormField>

            <SyvoraFormField label="Responsible (optional)" for="cert-responsible">
                <select
                    id="cert-responsible"
                    v-model="formResponsibleUserId"
                    class="certs-select"
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
.certs {
    max-width: 960px;
    margin: 0 auto;
}

.certs-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 1rem;
    margin-bottom: 1.5rem;
}

@media (max-width: 600px) {
    .certs-header {
        flex-direction: column;
        align-items: stretch;
    }
}

@media (max-width: 360px) {
    .certs-header h1 {
        font-size: 1.25rem;
    }

    .certs-card {
        padding: 0.75rem;
    }

    .certs-card-name {
        font-size: 0.875rem;
    }

    .certs-pills :deep(.badge) {
        font-size: 0.6875rem;
    }
}

.certs-cards {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
}

.certs-card-link {
    text-decoration: none;
    color: inherit;
}

.certs-card {
    display: flex;
    flex-direction: column;
    gap: 0.625rem;
    padding: 0.875rem 1rem;
}

.certs-card-top {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 0.5rem;
    flex-wrap: wrap;
}

.certs-card-name {
    font-weight: 600;
    font-size: 0.9375rem;
    color: var(--color-text);
    flex: 1;
    min-width: 0;
    word-break: break-word;
    overflow-wrap: anywhere;
}

.certs-card-top :deep(.badge) {
    flex-shrink: 0;
}

.certs-card-row {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 0.75rem;
    font-size: 0.8125rem;
    color: var(--color-text);
}

.certs-card-label {
    color: var(--color-text-muted);
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-weight: 600;
    flex-shrink: 0;
}

.certs-card-row > span:last-child {
    text-align: right;
    min-width: 0;
    word-break: break-word;
    overflow-wrap: anywhere;
}

.certs-header h1 {
    font-size: 1.5rem;
    font-weight: 700;
    margin: 0 0 0.5rem;
}

.certs-pills {
    display: flex;
    gap: 0.375rem;
    flex-wrap: wrap;
}

.certs-loading {
    text-align: center;
    color: var(--color-text-muted);
    padding: 2rem 0;
}

.certs-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.875rem;
}

.certs-table th {
    text-align: left;
    padding: 0.625rem 0.75rem;
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-muted);
    border-bottom: 1px solid rgba(0, 0, 0, 0.08);
}

.certs-table td {
    padding: 0.75rem;
    border-bottom: 1px solid rgba(0, 0, 0, 0.04);
}

.certs-table tr:last-child td {
    border-bottom: none;
}

.certs-name-link {
    color: var(--color-text);
    text-decoration: none;
    font-weight: 500;
}

.certs-name-link:hover {
    color: var(--color-accent);
    text-decoration: underline;
}

.certs-select {
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
