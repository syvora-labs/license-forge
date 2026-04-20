import { useMandator } from '../composables/useMandator'

const { MODULE_DEFINITIONS } = useMandator()

MODULE_DEFINITIONS.push({
    route: 'certificates',
    column: 'module_certificates',
    label: 'Certificates',
})

MODULE_DEFINITIONS.push({
    route: 'licenses',
    column: 'module_licenses',
    label: 'Licenses',
})
