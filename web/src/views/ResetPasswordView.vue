<script setup lang="ts">
import { ref } from 'vue'
import { SyvoraCard, SyvoraInput, SyvoraButton, SyvoraAlert, SyvoraFormField } from '@syvora/ui'
import { useAuth } from '../composables/useAuth'

const { resetPassword } = useAuth()

const email = ref('')
const error = ref('')
const success = ref(false)
const loading = ref(false)

async function handleSubmit() {
    error.value = ''
    loading.value = true
    try {
        await resetPassword(email.value)
        success.value = true
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to send reset link'
    } finally {
        loading.value = false
    }
}
</script>

<template>
    <div class="auth-page">
        <SyvoraCard title="Reset password">
            <form @submit.prevent="handleSubmit" class="auth-form">
                <SyvoraAlert v-if="success" variant="info">
                    Check your email for a reset link.
                </SyvoraAlert>

                <SyvoraAlert v-if="error" variant="error" dismissible @dismiss="error = ''">
                    {{ error }}
                </SyvoraAlert>

                <template v-if="!success">
                    <SyvoraFormField label="Email" for="reset-email">
                        <SyvoraInput
                            id="reset-email"
                            v-model="email"
                            placeholder="you@example.com"
                            type="email"
                            autocomplete="email"
                        />
                    </SyvoraFormField>

                    <SyvoraButton full :loading="loading" :disabled="!email">
                        Send reset link
                    </SyvoraButton>
                </template>

                <div class="auth-links">
                    <RouterLink to="/login" class="auth-link">Back to sign in</RouterLink>
                </div>
            </form>
        </SyvoraCard>
    </div>
</template>

<style scoped>
.auth-page {
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 1rem;
}

.auth-page :deep(.card) {
    width: 100%;
    max-width: 400px;
}

.auth-form {
    display: flex;
    flex-direction: column;
    gap: 1rem;
}

.auth-links {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.5rem;
}

.auth-link {
    font-size: 0.8125rem;
    color: var(--color-accent);
    text-decoration: none;
}

.auth-link:hover {
    text-decoration: underline;
}
</style>
