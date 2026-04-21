---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/code-documenter/references/api-docs-nestjs-express.md
ported-at: 2026-04-17
adapted: true
---

# API docs — NestJS + Express

## NestJS (@nestjs/swagger)

### Baseline

```typescript
// main.ts
const config = new DocumentBuilder()
  .setTitle("Orders Service")
  .setDescription("Orders, fulfillment, and payments API.")
  .setVersion("1.4.0")
  .addBearerAuth()
  .build();

const document = SwaggerModule.createDocument(app, config);
SwaggerModule.setup("docs", app, document);
```

### Controller + decorators

```typescript
@ApiTags("orders")
@ApiBearerAuth()
@Controller("orders")
export class OrdersController {
  @Post()
  @HttpCode(201)
  @ApiOperation({ summary: "Create an order" })
  @ApiBody({ type: CreateOrderDto })
  @ApiCreatedResponse({ type: OrderDto })
  @ApiBadRequestResponse({ description: "Validation error" })
  @ApiUnauthorizedResponse({ description: "Unauthenticated" })
  @ApiConflictResponse({ description: "Out of stock or invalid coupon" })
  create(@Body() body: CreateOrderDto): Promise<OrderDto> { /* … */ }
}
```

### DTOs with `class-validator` + `@ApiProperty`

```typescript
export class CreateOrderItemDto {
  @ApiProperty({ example: "SKU-A1" })
  @IsString() @IsNotEmpty()
  sku!: string;

  @ApiProperty({ example: 2, minimum: 1 })
  @IsInt() @Min(1)
  qty!: number;
}

export class CreateOrderDto {
  @ApiProperty({ type: [CreateOrderItemDto] })
  @ValidateNested({ each: true }) @Type(() => CreateOrderItemDto)
  @ArrayMinSize(1)
  items!: CreateOrderItemDto[];

  @ApiPropertyOptional({ example: "WELCOME10" })
  @IsOptional() @IsString()
  coupon?: string;
}
```

### Global error shape

Use an `ExceptionFilter` to format errors consistently, then describe that
shape in a reusable schema (e.g. `ApiErrorDto`) referenced from
`@ApiResponse` decorators.

### Validation

```bash
# Dump the OpenAPI JSON for linting
node ./scripts/dump-openapi.js > openapi.json
npx @redocly/cli lint openapi.json
```

## Express (swagger-jsdoc + swagger-ui-express)

### Baseline

```typescript
import swaggerJsdoc from "swagger-jsdoc";
import swaggerUi from "swagger-ui-express";

const spec = swaggerJsdoc({
  definition: {
    openapi: "3.1.0",
    info: { title: "Orders Service", version: "1.4.0" },
    components: {
      securitySchemes: {
        bearerAuth: { type: "http", scheme: "bearer", bearerFormat: "JWT" },
      },
    },
    security: [{ bearerAuth: [] }],
  },
  apis: ["./src/routes/*.ts", "./src/schemas/*.ts"],
});

app.use("/docs", swaggerUi.serve, swaggerUi.setup(spec));
```

### Annotated route

```typescript
/**
 * @openapi
 * /orders:
 *   post:
 *     tags: [Orders]
 *     summary: Create an order
 *     security:
 *       - bearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: "#/components/schemas/CreateOrderRequest" }
 *     responses:
 *       "201":
 *         description: Created
 *         content: { application/json: { schema: { $ref: "#/components/schemas/Order" } } }
 *       "400": { $ref: "#/components/responses/ValidationError" }
 *       "401": { $ref: "#/components/responses/Unauthorized" }
 *       "409": { $ref: "#/components/responses/Conflict" }
 */
router.post("/orders", createOrder);
```

### Rules

- Keep schemas in a central file (`schemas/*.ts`) and reference with `$ref`.
- Describe every response code, not just the happy path.
- Keep `info.version` aligned with the package version and bump on breaking
  changes.

## Cross-cutting rules

- One OpenAPI spec per service.
- One shared `ErrorBody` schema used everywhere.
- `operationId`s are unique and stable (tooling uses them as function names).
- `tags` used to group related endpoints — 5–15 operations per tag is a
  good target.
- Run a linter in CI (`redocly lint` or `spectral lint`) and fail the build
  on regressions.
- When generating client SDKs, pin the generator version and treat the
  generated client as an artifact, not a source.

## Choosing a style

| Concern | NestJS | Express |
|---|---|---|
| Schema source | DTOs + decorators | JSDoc on routes |
| Validation library | `class-validator` | `zod` / `joi` |
| Central error handling | ExceptionFilter | error middleware |
| Common gap | Missing `@ApiResponse` per status | Missing shared schemas; duplication |
