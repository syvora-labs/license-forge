<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { SyvoraCard, SyvoraInput, SyvoraButton, SyvoraAlert, SyvoraFormField } from '@syvora/ui'
import { useAuth } from '../composables/useAuth'

const router = useRouter()
const { updatePassword } = useAuth()

const password = ref('')
const confirmPassword = ref('')
const error = ref('')
const loading = ref(false)

async function handleSubmit() {
    error.value = ''
    if (password.value !== confirmPassword.value) {
        error.value = 'Passwords do not match'
        return
    }
    loading.value = true
    try {
        await updatePassword(password.value)
        router.push('/')
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to update password'
    } finally {
        loading.value = false
    }
}
</script>

<template>
    <div class="auth-page">
        <SyvoraCard title="Set new password">
            <form @submit.prevent="handleSubmit" class="auth-form">
                <SyvoraAlert v-if="error" variant="error" dismissible @dismiss="error = ''">
                    {{ error }}
                </SyvoraAlert>

                <SyvoraFormField label="New password" for="new-password">
                    <SyvoraInput
                        id="new-password"
                        v-model="password"
                        placeholder="New password"
                        type="password"
                        autocomplete="new-password"
                    />
                </SyvoraFormField>

                <SyvoraFormField label="Confirm password" for="confirm-password">
                    <SyvoraInput
                        id="confirm-password"
                        v-model="confirmPassword"
                        placeholder="Confirm password"
                        type="password"
                        autocomplete="new-password"
                        :error="confirmPassword && password !== confirmPassword ? 'Passwords do not match' : undefined"
                    />
                </SyvoraFormField>

                <SyvoraButton full :loading="loading" :disabled="!password || !confirmPassword">
                    Update password
                </SyvoraButton>
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
</style>
