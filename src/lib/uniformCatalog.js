
const DOUBLE_SIZE_ORDER = ['CD', 'EF', 'GH', 'IJ', 'KN', 'OP', 'QR', 'TU', 'VY']
const SINGLE_SIZE_ORDER = ['C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'N', 'O', 'P', 'Q', 'R', 'T', 'U', 'V', 'Y']
const ACCESSORY_SIZE_ORDER = ['ONE SIZE']

export function normalizeText(value) {
  return String(value ?? '').replaceAll('\xa0', ' ').trim()
}

export function inferSizeCategory(productType, fit) {
  const product = normalizeText(productType).toLowerCase()
  const normalizedFit = normalizeText(fit).toLowerCase()

  if (product.includes('beanie') || product.includes('apron') || product.includes('bandana') || product.includes('hat') || product.includes('accessor')) {
    return 'accessories'
  }

  const isBottom =
    product.includes('pant') ||
    product.includes('short') ||
    product.includes('bottom') ||
    product.includes('vest')

  const isSingleTop = product.includes('button-up')

  if (isSingleTop) {
    return normalizedFit === 'straight' ? 'straight_tops_single' : 'shaped_tops_single'
  }

  if (isBottom) {
    return normalizedFit === 'straight' ? 'straight_bottoms' : 'shaped_bottoms'
  }

  return normalizedFit === 'straight' ? 'straight_tops' : 'shaped_tops'
}

export function sortSizes(a, b) {
  const left = normalizeText(a).toUpperCase()
  const right = normalizeText(b).toUpperCase()
  const groups = [DOUBLE_SIZE_ORDER, SINGLE_SIZE_ORDER, ACCESSORY_SIZE_ORDER]

  for (const group of groups) {
    const leftIndex = group.indexOf(left)
    const rightIndex = group.indexOf(right)
    if (leftIndex >= 0 || rightIndex >= 0) {
      if (leftIndex === -1) return 1
      if (rightIndex === -1) return -1
      return leftIndex - rightIndex
    }
  }

  return left.localeCompare(right)
}

export function formatInventoryLabel(item) {
  return [item?.product_type, item?.fit, item?.size].filter(Boolean).join(' · ')
}

export function getSizeChartRows(sizeChart, productType, fit) {
  const category = inferSizeCategory(productType, fit)
  const rows = (Array.isArray(sizeChart) ? sizeChart : []).filter((row) => normalizeText(row.category) === category)
  return rows.sort((a, b) => Number(a.sort_order || 999) - Number(b.sort_order || 999))
}

export function getSizeNote(row) {
  const parts = []
  if (row.chest_range) parts.push(`Chest ${row.chest_range}`)
  if (row.waist_range) parts.push(`Waist ${row.waist_range}`)
  if (row.hip_range) parts.push(`Low hip ${row.hip_range}`)
  if (row.fit_note) parts.push(row.fit_note)
  return parts.filter(Boolean).join(' · ')
}
