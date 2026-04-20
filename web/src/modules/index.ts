import { useMandator } from '../composables/useMandator'

const { MODULE_DEFINITIONS } = useMandator()

MODULE_DEFINITIONS.push({
    route: 'certificates',
    column: 'module_certificates',
    label: 'Certificates',
})
