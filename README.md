# IKEA Uniform Portal (enhanced)

This package is a drop-in refresh for the Uniform Portal with the features you asked for:

- Admin dashboard with overall analytics
- History log of all co-worker requests
- Size chart
- Centralized employee list with CRUD
- Public request flow with auto-fill by employee ID
- Full SQL reset file for recreating the database from zero

## Routes

- `/request`
- `/admin/login`
- `/admin`
- `/admin/requests`
- `/admin/inventory`
- `/admin/employees`
- `/admin/size-chart`

## Setup

1. Run `supabase/schema.sql` in Supabase SQL Editor.
2. Add your env variables from `.env.example`.
3. Create your first auth user in Supabase Authentication.
4. Promote that user to admin in `profiles` by changing the `role`.
5. Install dependencies and run:
   ```bash
   npm install
   npm run dev
   ```

## Notes

- The public request page auto-fills `employee_name`, `employee_email`, and `department` from `employee_directory`.
- The SQL includes views for dashboard analytics and functions for employee lookup and request submission.
- The admin dashboard reads from analytics views:
  - `analytics_requested_sizes`
  - `analytics_most_ordered_items`
  - `analytics_requests_by_status`
  - `analytics_low_stock_items`
