import { Card, PageHeader } from '../components/ui'
import { sizeChart } from '../lib/portalApi'

export default function AdminSizeChartPage() {
  return (
    <>
      <PageHeader title="Size chart" description="Reference chart that co-workers and admins can use when selecting sizes." />

      <Card title="Uniform size reference" subtitle="Update this array in src/lib/portalApi.js if your local size guide changes.">
        <div className="overflow-x-auto">
          <table className="min-w-full border-separate border-spacing-y-2">
            <thead>
              <tr className="text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                <th className="px-4 py-2">Product</th>
                <th className="px-4 py-2">Fit</th>
                <th className="px-4 py-2">XS</th>
                <th className="px-4 py-2">S</th>
                <th className="px-4 py-2">M</th>
                <th className="px-4 py-2">L</th>
                <th className="px-4 py-2">XL</th>
                <th className="px-4 py-2">XXL</th>
              </tr>
            </thead>
            <tbody>
              {sizeChart.map((row) => (
                <tr key={`${row.product}-${row.fit}`} className="rounded-2xl bg-softBg text-sm text-slate-700">
                  <td className="rounded-l-2xl px-4 py-3 font-semibold">{row.product}</td>
                  <td className="px-4 py-3">{row.fit}</td>
                  <td className="px-4 py-3">{row.xs}</td>
                  <td className="px-4 py-3">{row.s}</td>
                  <td className="px-4 py-3">{row.m}</td>
                  <td className="px-4 py-3">{row.l}</td>
                  <td className="px-4 py-3">{row.xl}</td>
                  <td className="rounded-r-2xl px-4 py-3">{row.xxl}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </>
  )
}
