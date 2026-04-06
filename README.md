# Uniform Portal

Updated build with:

- request size dropdown driven by live inventory count
- deduplicated inventory seed rebuilt from `Uniform Inventory Count.xlsx`
- IKEA size chart seed prepared from the provided PDF
- optional `sku` field in the database

## Run locally

```bash
npm install
npm run dev
```

## Supabase SQL

Run in this order:

1. `supabase/schema.sql`
2. `supabase/seed.sql`

## Main change

The public request page now limits the size select to rows that still have free units:

- `free_units = stock_quantity - reserved_quantity`
- only sizes with `free_units > 0` appear in the request dropdown
- admin inventory still keeps the full inventory list for stock updates
