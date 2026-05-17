---
id: B2
role: builder
language: python
tags: [abstraction, premature-abstraction]
applicable_task_types: [new-feature, bugfix, refactor]
scope: medium
specializes: [P-SMALL-MODULES-01]
---

### Card B2: Premature abstraction

**Good:**
```python
def send_welcome_email(user: User) -> None:
    body = f"Welcome, {user.name}!\n\nGet started: {SETUP_URL}"
    smtp.send(to=user.email, subject="Welcome", body=body)
```

**Worse:**
```python
class EmailTemplateRenderer(ABC):
    @abstractmethod
    def render(self, context: dict) -> str: ...

class WelcomeEmailTemplate(EmailTemplateRenderer):
    def render(self, context: dict) -> str:
        return f"Welcome, {context['name']}!\n\nGet started: {context['setup_url']}"

class EmailService:
    def __init__(self, renderer: EmailTemplateRenderer, smtp_client: SMTPClient):
        self.renderer = renderer
        self.smtp_client = smtp_client

    def send(self, user: User) -> None:
        context = {"name": user.name, "setup_url": SETUP_URL}
        body = self.renderer.render(context)
        self.smtp_client.send(to=user.email, subject="Welcome", body=body)
```

**Why good is better:** Three classes and an abstract base to send one email. None of the abstractions have earned their cost — there is one template, one renderer, one service. Add abstractions when you have a concrete second use case, not in anticipation of one.
