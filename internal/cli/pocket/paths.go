package pocket

import "fmt"

const (
	// BackupKind is the document kind for Pocket ID SQLite backups under pocket/<instance>/.
	BackupKind = "PocketIDDatabaseBackup"
	BackupAPI  = "sealhub.io/v1"
)

// DBDocumentPath is the SealHub API path for the database backup (plain YAML envelope, pocket/ prefix).
func DBDocumentPath(instance string) string {
	return fmt.Sprintf("pocket/%s/pocket-id.db.yaml", instance)
}

// EnvDocumentPath is the SealHub API path for compose .env (encrypted secrets/ prefix).
func EnvDocumentPath(instance string) string {
	return fmt.Sprintf("secrets/%s/pocket-id.env", instance)
}
