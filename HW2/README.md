# HW2

## Версии и установка
Окружение:

- Foundry / Forge 1.3.1;
- Solidity 0.8.24, EVM Paris, optimizer: 200 runs;
- OpenZeppelin Contracts 5.0.2;
- forge-std 1.9.7

Установите Foundry, затем выберите версию:

```sh
foundryup --install v1.3.1
```

Библиотеки включены в lib/, отдельно устанавливать их не нужно

## Запуск

Из корня репозитория:

```sh
cd HW2
forge build
forge test -vv
forge fmt --check
```

## Пример approve + взнос

Пример взноса 10 TRIP для уже развёрнутых контрактов
RPC_URL - адрес RPC, TOKEN - адрес токена, FUND - адрес фонда
contributor - заранее импортированный в Cast аккаунт с балансом не меньше 10 TRIP и средствами на комиссию сети

Сначала участник разрешает фонду списать токены, затем отправляет взнос с того же аккаунта

```sh
cast send "$TOKEN" 'approve(address,uint256)' "$FUND" 10000000000000000000 \
  --rpc-url "$RPC_URL" --account contributor
cast send "$FUND" 'contribute(uint256)' 10000000000000000000 \
  --rpc-url "$RPC_URL" --account contributor
```
