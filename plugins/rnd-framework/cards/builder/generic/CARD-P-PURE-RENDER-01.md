---
id: P-PURE-RENDER-01
role: builder
language: generic
tags: [abstraction, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
---

### Card P-PURE-RENDER-01: Render/transform functions are pure data→UI

**Good:**
```typescript
type InvoiceRow = { label: string; amount: number; overdue: boolean }

const InvoiceItem = ({ label, amount, overdue }: InvoiceRow) => (
  <li className={overdue ? 'text-red-600' : ''}>
    {label}: {formatCurrency(amount)}
  </li>
)
```

**Worse:**
```typescript
const InvoiceItem = ({ invoiceId }: { invoiceId: string }) => {
  const [data, setData] = useState<InvoiceRow | null>(null)

  useEffect(() => {
    fetch(`/api/invoices/${invoiceId}`).then(r => r.json()).then(setData)
  }, [invoiceId])

  if (!data) {
    return <li>Loading…</li>
  }

  return (
    <li className={data.overdue ? 'text-red-600' : ''}>
      {data.label}: {formatCurrency(data.amount)}
    </li>
  )
}
```

**Why good is better:** The worse component owns its data-fetching, so you can't render it without a running API — testing it requires mocks, msw, or an integration harness. The good component is a pure function from props to markup: snapshot-testable with a single call, composable anywhere. Fetch data at the boundary (route loader, server action, page component); hand shaped data to render functions. Keep transforms pure.
