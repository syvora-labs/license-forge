<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { SyvoraCard, SyvoraInput, SyvoraButton, SyvoraAlert, SyvoraFormField } from '@syvora/ui'
import { useAuth } from '../composables/useAuth'

const router = useRouter()
const { signIn } = useAuth()

const email = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)

async function handleSubmit() {
    error.value = ''
    loading.value = true
    try {
        await signIn(email.value, password.value)
        router.push('/')
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Sign in failed'
    } finally {
        loading.value = false
    }
}
</script>

<template>
    <div class="auth-page">
        <SyvoraCard title="Sign in">
            <form @submit.prevent="handleSubmit" class="auth-form">
                <SyvoraAlert v-if="error" variant="error" dismissible @dismiss="error = ''">
                    {{ error }}
                </SyvoraAlert>

                <SyvoraFormField label="Email" for="email">
                    <SyvoraInput
                        id="email"
                        v-model="email"
                        placeholder="you@example.com"
                        type="email"
                        autocomplete="email"
                    />
                </SyvoraFormField>

                <SyvoraFormField label="Password" for="password">
                    <SyvoraInput
                        id="password"
                        v-model="password"
                        placeholder="Password"
                        type="password"
                        autocomplete="current-password"
                    />
                </SyvoraFormField>

                <SyvoraButton full :loading="loading" :disabled="!email || !password">
                    Sign in
                </SyvoraButton>

                <div class="auth-links">
                    <RouterLink to="/reset-password" class="auth-link">Forgot password?</RouterLink>
                    <RouterLink to="/signup" class="auth-link">Don't have an account? Sign up</RouterLink>
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
