export function Footer() {
  const year = new Date().getFullYear()

  return (
    <footer className="footer">
      <div className="container footer-inner">
        <div className="footer-legal">
          <strong>METAPHASIC GROUP CORPORATION</strong>
          1991 Crocker Rd, Westlake, OH 44145-6969, United States
        </div>
        <div className="footer-meta">
          <a href="https://metaphasic.net">metaphasic.net</a>
          <br />© {year} metaPhasic Group. All rights reserved.
        </div>
      </div>
    </footer>
  )
}
