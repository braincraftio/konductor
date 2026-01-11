import { defineCollection, z } from 'astro:content';

const docs = defineCollection({
	schema: z.object({
		title: z.string(),
		description: z.string(),
        section: z.string().default('Guide'),
		order: z.number().default(99),
	}),
});

export const collections = { docs };
