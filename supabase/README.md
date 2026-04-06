# Uniform Portal SQL

Run these files in order:

1. `supabase/schema.sql`
2. `supabase/seed.sql`

## Notes

- `inventory_items.inventory_key` is the deduplicated natural key used by the seed.
- `sku` is now optional and can stay null until that feature is ready.
- The public request page only shows size options that still have free inventory count.
- The seed inventory was rebuilt from `Uniform Inventory Count.xlsx` and merged into unique rows.
