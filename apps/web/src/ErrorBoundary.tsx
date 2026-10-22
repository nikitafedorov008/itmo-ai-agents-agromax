import { Component, type ReactNode } from "react";
export class ErrorBoundary extends Component<
  { children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    if (this.state.failed)
      return (
        <main className="loading-state" role="alert">
          <h1>Не удалось показать рабочее место</h1>
          <p>
            Обновите страницу. Если ошибка повторится, выйдите и войдите заново.
            Сохранённые на сервере данные останутся доступны.
          </p>
          <div className="button-row">
            <button className="primary" onClick={() => location.reload()}>
              Обновить страницу
            </button>
            <button
              className="outline"
              onClick={() => {
                sessionStorage.removeItem("agromax.session");
                location.reload();
              }}
            >
              Выйти из аккаунта
            </button>
          </div>
        </main>
      );
    return this.props.children;
  }
}
