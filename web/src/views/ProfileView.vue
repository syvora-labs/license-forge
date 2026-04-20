<script setup lang="ts">
import { ref, onMounted } from 'vue'
import {
    SyvoraCard,
    SyvoraInput,
    SyvoraButton,
    SyvoraAlert,
    SyvoraFormField,
    SyvoraAvatar,
} from '@syvora/ui'
import { useProfile } from '../composables/useProfile'

const { profile, loading, fetchProfile, updateProfile, uploadAvatar } = useProfile()

const displayName = ref('')
const error = ref('')
const success = ref(false)
const saving = ref(false)
const fileInput = ref<HTMLInputElement | null>(null)

onMounted(async () => {
    await fetchProfile()
    if (profile.value) {
        displayName.value = profile.value.display_name ?? ''
    }
})

async function handleSave() {
    error.value = ''
    success.value = false
    saving.value = true
    try {
        await updateProfile({ display_name: displayName.value })
        success.value = true
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to save'
    } finally {
        saving.value = false
    }
}

function triggerUpload() {
    fileInput.value?.click()
}

async function handleFileChange(event: Event) {
    const file = (event.target as HTMLInputElement).files?.[0]
    if (!file) return
    error.value = ''
    try {
        await uploadAvatar(file)
    } catch (e: unknown) {
        error.value = e instanceof Error ? e.message : 'Failed to upload avatar'
    }
}
</script>

<template>
    <div class="profile-page">
        <SyvoraCard title="Profile">
            <div v-if="loading" class="profile-loading">Loading...</div>

            <form v-else-if="profile" @submit.prevent="handleSave" class="profile-form">
                <SyvoraAlert v-if="success" variant="info" dismissible @dismiss="success = false">
                    Profile updated.
                </SyvoraAlert>

                <SyvoraAlert v-if="error" variant="error" dismissible @dismiss="error = ''">
                    {{ error }}
                </SyvoraAlert>

                <div class="profile-avatar-section">
                    <SyvoraAvatar
                        :name="profile.display_name || profile.email"
                        :src="profile.avatar_url"
                        size="lg"
                        editable
                        @click="triggerUpload"
                    />
                    <input
                        ref="fileInput"
                        type="file"
                        accept="image/*"
                        class="sr-only"
                        @change="handleFileChange"
                    />
                </div>

                <SyvoraFormField label="Display name" for="display-name">
                    <SyvoraInput
                        id="display-name"
                        v-model="displayName"
                        placeholder="Your name"
                    />
                </SyvoraFormField>

                <SyvoraFormField label="Email" for="profile-email">
                    <SyvoraInput
                        id="profile-email"
                        :model-value="profile.email"
                        disabled
                    />
                </SyvoraFormField>

                <SyvoraButton full :loading="saving">
                    Save
                </SyvoraButton>
            </form>
        </SyvoraCard>
    </div>
</template>

<style scoped>
.profile-page {
    max-width: 480px;
    margin: 0 auto;
}

.profile-form {
    display: flex;
    flex-direction: column;
    gap: 1rem;
}

.profile-avatar-section {
    display: flex;
    justify-content: center;
}

.profile-loading {
    text-align: center;
    color: var(--color-text-muted);
    padding: 2rem 0;
}

.sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    border: 0;
}
</style>
