/// Ministry identity is separate from the account's editing role.
bool accountIsPastor(Map<String, dynamic> account) =>
    account['role'] == 'gembala' || account['isPastor'] == true;
