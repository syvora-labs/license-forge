<script setup lang="ts">
import { ref } from 'vue'
import { SyvoraCard, SyvoraInput, SyvoraButton, SyvoraAlert, SyvoraFormField } from '@syvora/ui'
import { useAuth } from '../composables/useAuth'

const { signUp } = useAuth()

const email = ref('')
const password = ref('')
const confirmPassword = ref('')
const error = ref('')
const success = ref(false)
const loading = ref(false)

async function handleSubmit() {
    error.value = ''
    if (password.value !== confirmPassword.value) {
        error.value = 'Passwords do not match'
        return
    }
    loading.value = true
    try {
        await signUp(email.value, password.value)
        success.value = true
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Sign up failed'
    } finally {
        loading.value = false
    }
}
</script>

<template>
    <div class="auth-page">
        <SyvoraCard title="Create account">
            <form @submit.prevent="handleSubmit" class="auth-form">
                <SyvoraAlert v-if="success" variant="info">
                    Check your email to confirm your account.
                </SyvoraAlert>

                <SyvoraAlert v-if="error" variant="error" dismissible @dismiss="error = ''">
                    {{ error }}
                </SyvoraAlert>

                <template v-if="!success">
                    <SyvoraFormField label="Email" for="signup-email">
                        <SyvoraInput
                            id="signup-email"
                            v-model="email"
                            placeholder="you@example.com"
                            type="email"
                            autocomplete="email"
                        />
                    </SyvoraFormField>

                    <SyvoraFormField label="Password" for="signup-password">
                        <SyvoraInput
                            id="signup-password"
                            v-model="password"
                            placeholder="Password"
                            type="password"
                            autocomplete="new-password"
                        />
                    </SyvoraFormField>

                    <SyvoraFormField label="Confirm password" for="signup-confirm">
                        <SyvoraInput
                            id="signup-confirm"
                            v-model="confirmPassword"
                            placeholder="Confirm password"
                            type="password"
                            autocomplete="new-password"
                            :error="confirmPassword && password !== confirmPassword ? 'Passwords do not match' : undefined"
                        />
                    </SyvoraFormField>

                    <SyvoraButton full :loading="loading" :disabled="!email || !password || !confirmPassword">
                        Sign up
                    </SyvoraButton>
                </template>

                <div class="auth-links">
                    <RouterLink to="/login" class="auth-link">Already have an account? Sign in</RouterLink>
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
