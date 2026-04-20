import { ref } from 'vue'
import { supabase } from '../lib/supabase'

export interface Profile {
    id: string
    email: string
    display_name: string | null
    avatar_url: string | null
    created_at: string
    updated_at: string
}

const profile = ref<Profile | null>(null)
const loading = ref(false)

async function fetchProfile() {
    loading.value = true
    try {
        const { data: { user } } = await supabase.auth.getUser()
        if (!user) return

        const { data, error } = await supabase
            .from('profiles')
            .select('*')
            .eq('id', user.id)
            .single()

        if (error) throw error
        profile.value = data as Profile
    } finally {
        loading.value = false
    }
}

async function updateProfile(fields: { display_name?: string; avatar_url?: string }) {
    if (!profile.value) return

    const { data, error } = await supabase
        .from('profiles')
        .update(fields)
        .eq('id', profile.value.id)
        .select()
        .single()

    if (error) throw error
    profile.value = data as Profile
}

async function uploadAvatar(file: File) {
    if (!profile.value) return

    const ext = file.name.split('.').pop()
    const path = `${profile.value.id}/avatar.${ext}`

    const { error: uploadError } = await supabase.storage
        .from('avatars')
        .upload(path, file, { upsert: true })

    if (uploadError) throw uploadError

    const { data: { publicUrl } } = supabase.storage
        .from('avatars')
        .getPublicUrl(path)

    await updateProfile({ avatar_url: `${publicUrl}?t=${Date.now()}` })
}

export function useProfile() {
    return {
        profile,
        loading,
        fetchProfile,
        updateProfile,
        uploadAvatar,
    }
}
